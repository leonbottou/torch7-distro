#include "luaT.h"
#include "THC.h"
#include "THLogAdd.h" /* DEBUG: WTF */

#include <thrust/transform.h>
#include <thrust/reduce.h>
#include <thrust/transform_reduce.h>
#include <thrust/functional.h>
#include <thrust/device_ptr.h>

#include "HardTanh.cu"
#include "Tanh.cu"
#include "ReLU.cu"
#include "Max.cu"
#include "LogSoftMax.cu"
#include "TemporalConvolution.cu"
#include "SpatialConvolution.cu"
#include "SpatialConvolutionMap.cu"
#include "SpatialConvolutionCUDA.cu"
#include "SpatialSubSampling.cu"
#include "SpatialMaxPooling.cu"
#include "SpatialMaxPoolingCUDA.cu"
#include "Square.cu"
#include "Sqrt.cu"
#include "MultiMarginCriterion.cu"
#include "MSECriterion.cu"
#include "Threshold.cu"
#include "Sigmoid.cu"
#include "AbsCriterion.cu"
#include "Abs.cu"

// local changes
#include "CrossMapNormalization.cu"
#include "CrossMapNormalizationNew.cu"
#include "SpatialConvolutionNew.cu"
#include "SpatialMaxPoolingNew.cu"
#include "SpatialGlobalMaxPoolingNew.cu"


LUA_EXTERNC DLL_EXPORT int luaopen_libcunn(lua_State *L);

int luaopen_libcunn(lua_State *L)
{
  lua_newtable(L);

  cunn_Tanh_init(L);
  cunn_ReLU_init(L);
  cunn_Sigmoid_init(L);
  cunn_Max_init(L);
  cunn_HardTanh_init(L);
  cunn_LogSoftMax_init(L);
  cunn_TemporalConvolution_init(L);
  cunn_SpatialConvolution_init(L);
  cunn_SpatialConvolutionCUDA_init(L);
  cunn_SpatialConvolutionMap_init(L);
  cunn_SpatialMaxPooling_init(L);
  cunn_SpatialMaxPoolingCUDA_init(L);
  cunn_SpatialSubSampling_init(L);
  cunn_MultiMarginCriterion_init(L);
  cunn_Square_init(L);
  cunn_Sqrt_init(L);
  cunn_Threshold_init(L);
  cunn_MSECriterion_init(L);
  cunn_AbsCriterion_init(L);
  cunn_Abs_init(L);

  // local changes
  cunn_CrossMapNormalization_init(L);
  cunn_CrossMapNormalizationNew_init(L);
  cunn_SpatialConvolutionNew_init(L);
  cunn_SpatialMaxPoolingNew_init(L);
  cunn_SpatialGlobalMaxPoolingNew_init(L);

  return 1;
}
