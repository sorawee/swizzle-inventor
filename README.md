Refer to [LICENSE](LICENSE) for the license and copyright information for this project.

1D stencil
----------
* src: cuda/myStencil/myStencil.cu

1D conv
-------
* dir: cuda/myStencil
* run: bash run1d.sh

2D conv
-------
For shmeme and our synthesized code.
* dir: cuda/myStencil
* run: bash run2d.sh

Baselines
* Iandola at el: https://github.com/forresti/convolution
* ArrayFire: cuda/arrayfire
* NPP: cuda/nppConvolution

Finite field multiplication
---------------------------
* src: https://github.com/mangpo/GpuBinFieldMult
* degree 32 & 64, varying # of mults: bash run_32_64.sh
* degree >= 64, fixed # of mults:     bash run_ge_64.sh

AoS-load-sum
------------
For shmem and our synthesized code.
* dir: cuda/r2c_sum
* run: bash run.sh

Trove: https://github.com/bryancatanzaro/trove

AoS-load-store
--------------
For shmem and our synthesized code.
* dir: cuda/r2c
* run: bash run.sh
