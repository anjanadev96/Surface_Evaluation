from setuptools import setup
from torch.utils.cpp_extension import BuildExtension, CUDAExtension, CppExtension


setup(
    name='surface_evaluation',
    ext_modules=[
        CUDAExtension(name='surf_eval_cuda',
            sources=['surf_evaluation/csrc/surf_eval_cuda.cpp',
            'surf_evaluation/csrc/surf_eval_cuda_kernel.cu']),
        # CppExtension(name='surf_eval_cpp',
        # sources=['curve_evaluation/csrc/surf_eval.cpp'],
        # extra_include_paths=['surf_evaluation/csrc/surf_eval.h'])
    ],
    cmdclass={
        'build_ext': BuildExtension
    }
    
    )
