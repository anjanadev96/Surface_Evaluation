from setuptools import setup, find_packages
from torch.utils.cpp_extension import BuildExtension, CppExtension, CUDAExtension
import os
setup(
    name='surf_evaluation',
    ext_modules=[
        CUDAExtension(name='surf_eval_cuda',
            sources=['surf_evaluation/csrc/surf_eval_cuda.cpp',
            'surf_evaluation/csrc/surf_eval_cuda_kernel.cu']),



        # CppExtension(name='surf_eval_cpp',
        # sources=['surf_evaluation/csrc/surf_eval.cpp', 'surf_evaluation/csrc/utils.cpp'],
        # extra_include_paths=['surf_evaluation/csrc/surf_eval.h', 'surf_evaluation/csrc/utils.h'])
    ],
    cmdclass={
        'build_ext': BuildExtension
    },
    packages=find_packages(),)
