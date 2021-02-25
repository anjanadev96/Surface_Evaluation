#include <torch/extension.h>
#include <stdio.h>

#include <cuda.h>
#include <cuda_runtime.h>


#include <vector>


namespace {

__device__ __forceinline__ int find_span(int n, int p, float u, float* U)

{

double eps = 1.0e-4;
if (fabs(u-U[n+1]) < eps)
    return n;
int low = p;
int high = n+1;
int mid = (low + high)/2;
while (u < U[mid]-eps || u>=U[mid+1]+eps)
{ if (u < U[mid]-eps)
    high = mid;
    else
    low = mid;
    mid = (low+high)/2;
}
return mid;
}



__device__ __forceinline__ void basis_funs(int uspan_i, float u, int p, float* U, float* N, unsigned int i, unsigned int j)
{
  float saved, temp;
  int col = p + 1;
  N[i*col] = 1.0;
  if(j>0 && j < p + 1){
    saved = 0.0;
    for(int r = 0; r < j; r++){
      temp = N[i*col  + r]/((U[uspan_i + r + 1] - u) + (u - U[uspan_i  + 1 - j + r]));
      N[i*col+r] = saved + (U[uspan_i + r + 1] - u) * temp;
      saved = (u - U[uspan_i + 1 - j + r]) * temp;
    }
    N[i*col+j] = saved;
  }

}




__global__ void surf_cuda_pre_compute_basis_kernel(
    torch::PackedTensorAccessor<int,1,torch::RestrictPtrTraits,size_t> uspan,
    // torch::PackedTensorAccessor<float,2,torch::RestrictPtrTraits,size_t> Nu,
    torch::PackedTensorAccessor<float,1,torch::RestrictPtrTraits,size_t> u,
    float* U_ptr,
    float* Nu_ptr,
    int m, 
    int p, 
    int out_dim, 
    int _dimension,
    int u_size) {

    unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned int j = blockIdx.y * blockDim.y + threadIdx.y;
    

    if(i < u_size ){
      if (j < p+1){
      
      uspan[i] = find_span(m, p, u[i], U_ptr);
      // 
      

      basis_funs(uspan[i],u[i],p,U_ptr,Nu_ptr,i,j);

      }
    }
  }


__global__ void curve_cuda_forward_kernel(
  torch::PackedTensorAccessor<float,3,torch::RestrictPtrTraits,size_t> ctrl_pts,
  torch::PackedTensorAccessor<int,1,torch::RestrictPtrTraits,size_t> uspan,
  torch::PackedTensorAccessor<float,2,torch::RestrictPtrTraits,size_t> Nu,
  torch::PackedTensorAccessor<float,1,torch::RestrictPtrTraits,size_t> u,
  torch::PackedTensorAccessor<float,3,torch::RestrictPtrTraits,size_t> curves,
  // int* uspan,
  // float* Nu,
  int m,
  int p,
  int _dimension,
  unsigned int ctrl_pts_size,
  unsigned int u_size){

  unsigned int k = blockIdx.x * blockDim.x + threadIdx.x;
  unsigned int i = blockIdx.y * blockDim.y + threadIdx.y;
  unsigned int l = blockIdx.z * blockDim.z + threadIdx.z;
  // std::printf("Hello from k %d, i %d, l %d\n", k,i,l);


  if(k < ctrl_pts_size)
  { if (i< u_size)
    { if(l < (_dimension+1))
      { 
        for (int j = 0; j<=p; j++)
        {curves[k][i][l] = curves[k][i][l] + 
                                            Nu[i][j]*ctrl_pts[k][uspan[i]-p + j][l];
        }


  
      }

    }
  }
 }
   


   


}
















std::vector<torch::Tensor> surf_cuda_pre_compute_basis(
    torch::Tensor u,
    torch::Tensor U,
    // torch::Tensor uspan,
    // torch::Tensor Nu,
    int m,
    int p,
    int out_dim,
    int _dimension){
  
    float* U_ptr = (float*)U.data_ptr();
    auto options1 = torch::TensorOptions().dtype(torch::kInt32).device(torch::kCUDA, 0).requires_grad(false);
    auto options2 = torch::TensorOptions().dtype(torch::kFloat32).device(torch::kCUDA, 0).requires_grad(true);
    
    // auto device = torch::device(torch::kCUDA, 1);
    auto uspan = torch::zeros(u.size(0), options1);
    auto Nu = torch::zeros({u.size(0), p + 1}, options2);
    float* Nu_ptr = (float*)Nu.data_ptr();
  
    int u_size = u.size(0);
  
    const dim3 block(4, 4, 1);
    const dim3 grid(u_size/4+1, (p+1)/4+1, 1);
  
    // AT_DISPATCH_FLOATING_TYPES(u.type(), "curve_cuda_pre_compute", ([&] {
      curve_cuda_pre_compute_basis_kernel<<<grid, block>>>(
          uspan.packed_accessor<int,1,torch::RestrictPtrTraits,size_t>(),
          // Nu.packed_accessor<float,2,torch::RestrictPtrTraits,size_t>(),
          u.packed_accessor<float,1,torch::RestrictPtrTraits,size_t>(),
          U_ptr,
          Nu_ptr,
          m, 
          p, 
          out_dim, 
          _dimension,
          u_size);
    // }));
  
      return {uspan, Nu};
    
    }





torch::Tensor surf_cuda_forward(
    torch::Tensor ctrl_pts,
    torch::Tensor uspan,
    torch::Tensor Nu,
    torch::Tensor u,
    int m,
    int p,
    int _dimension){
    
    auto options = torch::TensorOptions().dtype(torch::kFloat32).device(torch::kCUDA, 0).requires_grad(true);
  
    // float* Nu_ptr = (float*)Nu.data_ptr();
    // int* uspan_ptr = (int*)uspan.data_ptr();
    auto curves = torch::zeros({ctrl_pts.size(0),u.size(0), _dimension+1}, options);
    unsigned int ctrl_pts_size = ctrl_pts.size(0);
    unsigned int u_size = u.size(0);
  
    const dim3 block(16, 16, 4);
    const dim3 grid((ctrl_pts_size)/16+1, (u_size)/16+1, 1);
  
  
    curve_cuda_forward_kernel<<<grid, block>>>(
      ctrl_pts.packed_accessor<float,3,torch::RestrictPtrTraits,size_t>(),
      uspan.packed_accessor<int,1,torch::RestrictPtrTraits,size_t>(),
      Nu.packed_accessor<float,2,torch::RestrictPtrTraits,size_t>(),
      u.packed_accessor<float,1,torch::RestrictPtrTraits,size_t>(),
      curves.packed_accessor<float,3,torch::RestrictPtrTraits,size_t>(),
      m, 
      p,  
      _dimension,
      ctrl_pts_size,
      u_size);
  
  
      return curves;
  
    }