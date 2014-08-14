#ifndef assert
#define assert(e)  \
    if (!(e)) { \
        printf("failed assertion `%s'\n", #e); \
        THError("aborting..."); \
    };
#endif

/*

This file contains 2 kernels :
- copyPixelsInSlices.
- addPixelsInSlices.

The primary kernel is copyPixelsInSlices : it unfolds a 3D matrix into a 2D matrix in a way that the 2D convolution (with many kernels) becomes a matrix multiplication.
We call the resulting matrix "kernelSlices". Each row corresponds to a kW*kH*nInputPlane array.

Steps :
1) choose a pixel (pixi = blockIdx.x, pixj = blockIdx.y)
2) find which slices (coordinates (imin-imax, jmin-jmax)) will contain the pixel information
3) loop : copy the pixel information, jump to next slice (and position) by 
		moving the kernelSlices pointer ptrkslices by stridej = (kH*kW - dW) * nInputPlane

	detailed example : pixel (4,4), kernels of size 5*5, stride dW=1 :
	- 1st slice  : top-left coordinates : (imin,jmin)  . Pixel is in coordinates (4,4, position 25) of the slice.
	- 2nd slice  : top-left coordinates : (imin,jmin+1). Pixel is in coordinates (4,3, position 24) of the slice.
	- 3rd slice  : top-left coordinates : (imin,jmin+2). Pixel is in coordinates (4,2, position 23) of the slice.
	- 4th slice  : top-left coordinates : (imin,jmin+2). Pixel is in coordinates (4,1, position 22) of the slice.
	- 5th slice  : top-left coordinates : (imin,jmin+2). Pixel is in coordinates (4,0, position 21) of the slice.
	- when jmax-jmin slices have been filled, we jump to the next series of slices by 
		moving ptrkslices by stridei = (((size2-jmax+jmin-1)*kH -dH)*kW  + (jmax-jmin+1)*dW)*nInputPlane
	- 1st slice  : top-left coordinates : (imin+1,jmin)  . Pixel is in coordinates (3,4, position 20) of the slice.
	- 2nd slice  : top-left coordinates : (imin+1,jmin+1). Pixel is in coordinates (3,3, position 19) of the slice.
	- 3rd slice  : top-left coordinates : (imin+1,jmin+2). Pixel is in coordinates (3,2, position 18) of the slice.
	- 4th slice  : top-left coordinates : (imin+1,jmin+2). Pixel is in coordinates (3,1, position 17) of the slice.
	- 5th slice  : top-left coordinates : (imin+1,jmin+2). Pixel is in coordinates (3,0, position 16) of the slice.
	- ...

In case the pixel (pixi,pixj) is in the zero-padding, we fill the slice with zeros.

addPixelsInSlices is the same, except we read the contents of the array instead of writing.

*/

__global__ void copyPixelsInSlices(float *ptrinput0, float *ptrkslices0,
	int dH, int dW, int kH, int kW, int size1, int size2, int isize1, int isize2, int nInputPlane, int padleft, int padright, int padup, int paddown, int inputstr0, int kslicesstr0, int batchsize)
{
	const int pixi=blockIdx.x;
	const int pixj=blockIdx.y;
	const int blk =blockDim.x*blockDim.y;
	const int tidx=threadIdx.x+blockDim.x*threadIdx.y;

	__shared__ int _imin, _jmin, _imax, _jmax, _stridej, _stridei, _ksliceoffset, _inputoffset;

	int imin, jmin, imax, jmax;
	int stridej, stridei, ksliceoffset, inputoffset;

	if(tidx==0)
	{
        imin=(pixi - (kH - 1) + (dH -1))/dH > 0 ? (pixi - (kH - 1) + (dH -1))/dH : 0 ;
        jmin=(pixj - (kW - 1) + (dW -1))/dW > 0 ? (pixj - (kW - 1) + (dW -1))/dW : 0 ;
        imax= pixi / dH < size1 ? pixi / dH : size1 - 1 ;
        jmax= pixj / dW < size2 ? pixj / dW : size2 - 1 ;
		  stridej = (kH*kW - dW) * nInputPlane;
        stridei = (((size2-jmax+jmin-1)*kH -dH)*kW  + (jmax-jmin+1)*dW)*nInputPlane;
		  ksliceoffset = ((imin * size2  + jmin) * kH * kW +  (pixi - imin * dH) * kW + (pixj - jmin*dW) ) * nInputPlane + kslicesstr0*blockIdx.z;
		  inputoffset = ((pixi-padup) * isize2 + (pixj-padleft)) * nInputPlane + inputstr0*blockIdx.z;
		  _imin=imin;
		  _jmin=jmin;
		  _imax=imax;
		  _jmax=jmax;
		  _stridej=stridej;
		  _stridei=stridei;
		  _ksliceoffset=ksliceoffset;
		  _inputoffset=inputoffset;

	}

	__syncthreads();

   if(threadIdx.x==0 && threadIdx.y>0)
	{
		imin=_imin;
		jmin=_jmin;
		imax=_imax;
		jmax=_jmax;
	   stridej=_stridej;
		stridei=_stridei;
		ksliceoffset=_ksliceoffset;
		inputoffset=_inputoffset;
	}

	imin=__shfl(imin, 0);
	jmin=__shfl(jmin, 0);
	imax=__shfl(imax, 0);
	jmax=__shfl(jmax, 0);
	stridej=__shfl(stridej, 0);
	stridei=__shfl(stridei, 0);
	ksliceoffset=__shfl(ksliceoffset, 0);
	inputoffset=__shfl(inputoffset, 0);

	int i;
	int j;
	int k;

	bool zeropad=pixi<padup || pixi>isize1-1+padup || pixj<padleft || pixj>isize2-1+padleft ;
	
	float * ptrinput    = ptrinput0 + inputoffset;
	float * ptrkslices  = ptrkslices0 + ksliceoffset;

	for(i=imin; i<imax+1; i++) {
		for(j=jmin; j<jmax+1; j++) {
			if(zeropad) 
			{
				for(k=tidx; k<nInputPlane; k+=blk) {
					ptrkslices[k]=0;
				}
			}
			else {
				for(k=tidx; k<nInputPlane; k+=blk) {
					ptrkslices[k]=ptrinput[k];
				}
			}
			ptrkslices += stridej;
		}
		ptrkslices += stridei;
	}	
}


/*__global__ void copyPixelsInSlicesRGB(float *ptrinput0, float *ptrkslices0,
	int dH, int dW, int kH, int kW, int size1, int size2, int isize1, int isize2, int nInputPlane, int padleft, int padright, int padup, int paddown, int inputstr0, int kslicesstr0, int batchsize)
{
	// each block does one pixel of the input image
	// each kernel slice is represented by its upper-left coordinates

	const int pixi=blockIdx.x;
	const int pixj=blockIdx.y*blockDim.y + threadIdx.y;
	const int tidx=threadIdx.x;

	int i,j,b;

	if(pixj > isize2 + padleft + padright -1) return;

	// step 1 : find which kernel slices contain the values of the pixel
        const int imin=(pixi - (kH - 1) + (dH -1))/dH > 0 ? (pixi - (kH - 1) + (dH -1))/dH : 0 ;
        const int jmin=(pixj - (kW - 1) + (dW -1))/dW > 0 ? (pixj - (kW - 1) + (dW -1))/dW : 0 ;
        const int imax= pixi / dH < size1 ? pixi / dH : size1 - 1 ;
        const int jmax= pixj / dW < size2 ? pixj / dW : size2 - 1 ;

	// step 2 : move the pointers
	// this one goes to where the pixel is at
	ptrinput0   += inputstr0*blockIdx.z + ((pixi-padup) * isize2 + (pixj-padleft)) * nInputPlane ;
	ptrkslices0 += kslicesstr0*blockIdx.z + ((imin * size2  + jmin) * kH * kW +  (pixi - imin * dH) * kW + (pixj - jmin*dW) ) * nInputPlane;

	const int stridej = (kH*kW - dW) * nInputPlane;
	const int stridei = (size2*kH-dH) * kW *nInputPlane - (jmax-jmin+1) * stridej ;

	bool zeropad = pixi<padup || pixi>isize1-1+padup || pixj<padleft || pixj>isize2-1+padleft ;


	// read pixel
	// load the stuff first...
	//for (b=0; b<batchsize; b++) 
	//{
		float * ptrinput    = ptrinput0;
		float * ptrkslices  = ptrkslices0;

		float pixvalue;
		if (zeropad) 	{
			pixvalue=0;
		}
		else	{
			pixvalue=ptrinput[tidx];
		}


	//	write to memory
		for(i=imin; i<imax+1; i++) {
			for(j=jmin; j<jmax+1; j++) {
				if(zeropad) 
				{
					ptrkslices[tidx]=0;
				}
				else {
					ptrkslices[tidx]=pixvalue;
				}
				ptrkslices += stridej;
			}
			ptrkslices += stridei;
		}	
	//}
}*/



__global__ void copyPixelsInSlicesRGB(float *ptrinput0, float *ptrkslices0,
	int dH, int dW, int kH, int kW, int size1, int size2, int isize1, int isize2, int nInputPlane, int padleft, int padright, int padup, int paddown, int inputstr0, int kslicesstr0, int batchsize)
{
	// each block [3,32] does 32 pixels of one row over x
	// each kernel slice is represented by its upper-left coordinates
   // pixi => y, pixj => x 

	const int pixi=threadIdx.y;
	const int pixj=blockIdx.y*blockDim.y + threadIdx.y;
	const int tidx=threadIdx.x;

	int i,j,b;

	if(pixj > isize2 + padleft + padright -1) return;

	// step 1 : find which kernel slices contain the values of the pixel
        const int imin=(pixi - (kH - 1) + (dH -1))/dH > 0 ? (pixi - (kH - 1) + (dH -1))/dH : 0 ;
        const int jmin=(pixj - (kW - 1) + (dW -1))/dW > 0 ? (pixj - (kW - 1) + (dW -1))/dW : 0 ;
        const int imax= pixi / dH < size1 ? pixi / dH : size1 - 1 ;
        const int jmax= pixj / dW < size2 ? pixj / dW : size2 - 1 ;

	// step 2 : move the pointers
	// this one goes to where the pixel is at
	ptrinput0   += inputstr0*blockIdx.z + ((pixi-padup) * isize2 + (pixj-padleft)) * nInputPlane ;
	ptrkslices0 += kslicesstr0*blockIdx.z + ((imin * size2  + jmin) * kH * kW +  (pixi - imin * dH) * kW + (pixj - jmin*dW) ) * nInputPlane;

	const int stridej = (kH*kW - dW) * nInputPlane;
	const int stridei = (size2*kH-dH) * kW *nInputPlane - (jmax-jmin+1) * stridej ;

	bool zeropad = pixi<padup || pixi>isize1-1+padup || pixj<padleft || pixj>isize2-1+padleft ;


	// read pixel
	// load the stuff first...
	//for (b=0; b<batchsize; b++) 
	//{
		float * ptrinput    = ptrinput0;
		float * ptrkslices  = ptrkslices0;

		float pixvalue;
		if (zeropad) 	{
			pixvalue=0;
		}
		else	{
			pixvalue=ptrinput[tidx];
		}


	//	write to memory
		for(i=imin; i<imax+1; i++) {
			for(j=jmin; j<jmax+1; j++) {
				if(zeropad) 
				{
					ptrkslices[tidx]=0;
				}
				else {
					ptrkslices[tidx]=pixvalue;
				}
				ptrkslices += stridej;
			}
			ptrkslices += stridei;
		}	
	//}
}




__global__ void addPixelsInSlices(float *ptrgradinput0, float *ptrkslices0,
	int dH, int dW, int kH, int kW, int size1, int size2, int isize1, int isize2, int nInputPlane, int padleft, int padright, int padup, int paddown, int gradinputstr0, int kslicesstr0, int batchsize)
{
	const int pixi=blockIdx.x;
	const int pixj=blockIdx.y;
	const int blk =blockDim.x*blockDim.y;
	const int tidx=threadIdx.x+blockDim.x*threadIdx.y;

	bool zeropad=pixi<padup || pixi>isize1-1+padup || pixj<padleft || pixj>isize2-1+padleft ;
	if(zeropad) return;
	
	__shared__ int _imin, _jmin, _imax, _jmax, _stridej, _stridei, _ksliceoffset, _gradinputoffset;
	int stridej, stridei, ksliceoffset, gradinputoffset;

	int imin;
	int jmin;
	int imax;
	int jmax;

	if(threadIdx.y==0 && threadIdx.x==0)
	{
        imin=(pixi - (kH - 1) + (dH -1))/dH > 0 ? (pixi - (kH - 1) + (dH -1))/dH : 0 ;
        jmin=(pixj - (kW - 1) + (dW -1))/dW > 0 ? (pixj - (kW - 1) + (dW -1))/dW : 0 ;
        imax= pixi / dH < size1 ? pixi / dH : size1 - 1 ;
        jmax= pixj / dW < size2 ? pixj / dW : size2 - 1 ;
		  stridej = (kH*kW - dW) * nInputPlane;
        stridei = (((size2-jmax+jmin-1)*kH -dH)*kW  + (jmax-jmin+1)*dW)*nInputPlane;
		  ksliceoffset = ((imin * size2  + jmin) * kH * kW +  (pixi - imin * dH) * kW + (pixj - jmin*dW) ) * nInputPlane + kslicesstr0*blockIdx.z;
		  gradinputoffset = ((pixi-padup) * isize2 + (pixj-padleft)) * nInputPlane + gradinputstr0*blockIdx.z;
		  _imin=imin;
		  _jmin=jmin;
		  _imax=imax;
		  _jmax=jmax;
		  _stridej=stridej;
		  _stridei=stridei;
		  _ksliceoffset=ksliceoffset;
		  _gradinputoffset=gradinputoffset;
	}

	__syncthreads();

   if(threadIdx.x==0 && threadIdx.y>0)
	{
		imin=_imin;
		jmin=_jmin;
		imax=_imax;
		jmax=_jmax;
	   stridej=_stridej;
		stridei=_stridei;
		ksliceoffset=_ksliceoffset;
		gradinputoffset=_gradinputoffset;
	}

	imin=__shfl(imin, 0);
	jmin=__shfl(jmin, 0);
	imax=__shfl(imax, 0);
	jmax=__shfl(jmax, 0);
	stridej=__shfl(stridej, 0);
	stridei=__shfl(stridei, 0);
	ksliceoffset=__shfl(ksliceoffset, 0);
	gradinputoffset=__shfl(gradinputoffset, 0);

	int i;
	int j;
	int k;

	for(k=tidx; k<nInputPlane; k+=blk) {
		float * ptrgradinput    = ptrgradinput0 + gradinputoffset;
		float * ptrkslices  		= ptrkslices0 + ksliceoffset;
		float v=0;
		for(i=imin; i<imax+1; i++) {
			for(j=jmin; j<jmax+1; j++) {
				v += ptrkslices[k];
				ptrkslices += stridej;
			}
			ptrkslices += stridei;
		}	
		ptrgradinput[k] += v;
	}
}



__global__ void copyBiasToOutputs(float *ptrbias, float *ptroutput, const int size1, const int size2, const int nOutputPlane, const int linestride, const int imstride)
{
	// each thread has a value to manage...
	//const int blk =blockDim.x;
	const int tidx=blockDim.x*blockIdx.x + threadIdx.x;
	const int tidy=blockIdx.y;
	const int tidz=blockIdx.z;	

	int i;

	float val = ptrbias[tidx];
	ptroutput+= tidz*imstride + tidy*linestride;

	for(int k=0; k<size2; k++)
	{
		if(tidx<nOutputPlane) {
			ptroutput[k*nOutputPlane+tidx]=val;
		}
	}
}


void copyBiasVector(THCudaTensor* output, THCudaTensor* bias)
{
		float* ptrbias    = THCudaTensor_data(bias);
		float* ptroutput  = THCudaTensor_data(output);
		int nOutputPlane	= bias->size[0];
		int batchsize		= output->size[0];
		int size1			= output->size[1];
		int size2			= output->size[2];
  		// fill output with biases
  		dim3 blocksbias ((nOutputPlane+31)/32, size1, batchsize);
  		dim3 threadsbias (32);
  		copyBiasToOutputs<<<blocksbias, threadsbias>>>(ptrbias, ptroutput, size1, size2, nOutputPlane, output->stride[1], output->stride[0]); 
}




__global__ void computeGradBias32(float *ptrgradbias, float *ptrgradoutput, const int size1, const int size2, const int nOutputPlane, float scale, const int batchsize, const int batchstride)
{
	const int tid = blockDim.x*blockIdx.x + threadIdx.x;
	const int tidx = threadIdx.x;
	const int tidy = threadIdx.y;
	const int numpix=size1*size2;
	
	__shared__ float values[32][32];

	float value = 0;
	int i,j;

	for(j=0; j<batchsize; j++)
	{
		for(i=0; i+tidy<numpix; i+=blockDim.y) {
			if (tid<nOutputPlane) {
			value += ptrgradoutput[j*batchstride+(i+tidy)*nOutputPlane+tid];
			}
		}
	}

	values[tidy][tidx]=value;
	__syncthreads();
	// reduction :

	if (tidy == 0) {
		float gradbiasvalue=0;
		#pragma unroll
		for(i=0; i<32;i++){ gradbiasvalue+=values[i][tidx]; }

		if (tid<nOutputPlane) {
			atomicAdd(&ptrgradbias[tid], scale*gradbiasvalue);
		}
	}
	
}




void sliceInput(THCudaTensor *input, THCudaTensor* kernelSlices, int kH, int kW, int dH, int dW, int padup, int paddown, int padleft, int padright)
{
  // find the size of kernelslices
  long batchsize = input->size[0];
  long isize1 = input->size[1];
  long isize2 = input->size[2];
  long nInputPlane = input->size[3];
  long size1 = (isize1 - kH + padup + paddown) / dH + 1;
  long size2 = (isize2 - kW + padleft + padright) / dW + 1;

  float* ptrkslices = THCudaTensor_data(kernelSlices);
  float* ptrinput   = THCudaTensor_data(input);

	int inputstr0=input->stride[0];
	int kslicesstr0=size1*size2*kW*kH*nInputPlane;


  //kernel unfold inputs
	if (nInputPlane ==3) 
	{
		dim3 blocksRGB (isize1 + padup + paddown, (isize2 + padleft + padright+9)/10, batchsize);
		dim3 threadsRGB (3,10);
		copyPixelsInSlicesRGB <<<blocksRGB, threadsRGB>>>(ptrinput, ptrkslices,
		dH, dW, kH, kW, size1, size2, isize1, isize2, nInputPlane, padleft, padright, padup, paddown, inputstr0, kslicesstr0, batchsize);
	}
	else 
	{
		int b_y;
		if (nInputPlane>1024) 
		{
			b_y=32;
		}
		else
		{
			b_y=(nInputPlane+31)/32;
		}
		dim3 blocks (isize1 + padup + paddown, isize2 + padleft + padright, batchsize);
		dim3 threads (32,b_y);
		copyPixelsInSlices<<<blocks, threads>>>(ptrinput, ptrkslices,
		dH, dW, kH, kW, size1, size2, isize1, isize2, nInputPlane, padleft, padright, padup, paddown, inputstr0, kslicesstr0, batchsize);
	}


}


void sliceInputSplit(THCudaTensor *input, THCudaTensor* kernelSlices, int kH, int kW, int dH, int dW, int padup, int paddown, int padleft, int padright, int numsplits=1, int splitid=0)
{
  // find the size of kernelslices
  long batchsize = input->size[0]/numsplits;
  long isize1 = input->size[1];
  long isize2 = input->size[2];
  long nInputPlane = input->size[3];
  long size1 = (isize1 - kH + padup + paddown) / dH + 1;
  long size2 = (isize2 - kW + padleft + padright) / dW + 1;

	int inputstr0=input->stride[0];
	int kslicesstr0=size1*size2*kW*kH*nInputPlane;

  float* ptrkslices = THCudaTensor_data(kernelSlices);
  float* ptrinput   = THCudaTensor_data(input)+splitid*inputstr0*batchsize;



  //kernel unfold inputs
	if (nInputPlane ==3) 
	{
		dim3 blocksRGB (isize1 + padup + paddown, (isize2 + padleft + padright+9)/10, batchsize);
		dim3 threadsRGB (3,10);
		copyPixelsInSlicesRGB <<<blocksRGB, threadsRGB>>>(ptrinput, ptrkslices,
		dH, dW, kH, kW, size1, size2, isize1, isize2, nInputPlane, padleft, padright, padup, paddown, inputstr0, kslicesstr0, batchsize);
	}
	else 
	{
		int b_y;
		if (nInputPlane>1024) 
		{
			b_y=32;
		}
		else
		{
			b_y=(nInputPlane+31)/32;
		}
		dim3 blocks (isize1 + padup + paddown, isize2 + padleft + padright, batchsize);
		dim3 threads (32,b_y);
		copyPixelsInSlices<<<blocks, threads>>>(ptrinput, ptrkslices,
		dH, dW, kH, kW, size1, size2, isize1, isize2, nInputPlane, padleft, padright, padup, paddown, inputstr0, kslicesstr0, batchsize);
	}


}

void unsliceGradient(THCudaTensor *backwardSlices, THCudaTensor *gradInput, THCudaTensor *gradOutput, int kH, int kW, int dH, int dW, int padup, int paddown, int padleft, int padright)
{

  long batchsize = gradInput->size[0];
  long isize1 = gradInput->size[1];
  long isize2 = gradInput->size[2];
  long nInputPlane = gradInput->size[3];
  long size1 = gradOutput->size[1];
  long size2 = gradOutput->size[2];

  float* ptrbackslices = THCudaTensor_data(backwardSlices);
  float* ptrgradinput  = THCudaTensor_data(gradInput);

	int b_y;
	if (nInputPlane>1024) 
	{
		b_y=32;
	}
	else
	{
		b_y=(nInputPlane+31)/32;
	}

  dim3 blocks (isize1 + padup + paddown, isize2 + padleft + padright, batchsize);
  dim3 threads (32,b_y);

	int gradinputstr0=gradInput->stride[0];
	int kslicesstr0=size1*size2*kW*kH*nInputPlane;

   addPixelsInSlices<<<blocks, threads>>>(ptrgradinput, ptrbackslices,
		dH, dW, kH, kW, size1, size2, isize1, isize2, nInputPlane, padleft, padright, padup, paddown, gradinputstr0, kslicesstr0, batchsize);

}




static int cunxn_SpatialConvolutionUnfold_updateOutput(lua_State *L)
{
  THCudaTensor *input = (THCudaTensor *)luaT_checkudata(L, 2, "torch.CudaTensor");
  THCudaTensor *output = (THCudaTensor *)luaT_getfieldcheckudata(L, 1, "output", "torch.CudaTensor");
  THCudaTensor *kernels = (THCudaTensor *)luaT_getfieldcheckudata(L, 1, "weight", "torch.CudaTensor");
  THCudaTensor *bias = (THCudaTensor *)luaT_getfieldcheckudata(L, 1, "bias", "torch.CudaTensor");
//  THCudaTensor *kSlices = (THCudaTensor *)luaT_getfieldcheckudata(L, 1, "kernelSlices", "torch.CudaTensor");
  long kW = luaT_getfieldcheckint(L, 1, "kW");
  long kH = luaT_getfieldcheckint(L, 1, "kH");
  long dW = luaT_getfieldcheckint(L, 1, "dW");
  long dH = luaT_getfieldcheckint(L, 1, "dH");
  long padup = luaT_getfieldcheckint(L, 1, "padtop");
  long paddown = luaT_getfieldcheckint(L, 1, "padbottom");
  long padleft = luaT_getfieldcheckint(L, 1, "padleft");
  long padright = luaT_getfieldcheckint(L, 1, "padright");
  long nOutputPlane = luaT_getfieldcheckint(L, 1, "nOutputPlane");
  long nInputPlane = luaT_getfieldcheckint(L, 1, "nInputPlane");

  // input should be contiguous already but... well.
  input = THCudaTensor_newContiguous(input);

  // find the size of kernelslices
  long batchsize = input->size[0];
  long isize1 = input->size[1];
  long isize2 = input->size[2];
  long size1 = (isize1 - kH + padup + paddown) / dH + 1;
  long size2 = (isize2 - kW + padleft + padright) / dW + 1;

  THCudaTensor_resize4d(output, batchsize, size1, size2, nOutputPlane);
  copyBiasVector(output, bias);

  // unfold conv kernels by resizing
  THCudaTensor_resize2d(kernels, nOutputPlane, kW*kH*nInputPlane);
  THCudaTensor_transpose(kernels, NULL, 0, 1);

  size_t freeMem;
  THCudaCheck(cudaMemGetInfo (&freeMem, NULL));

  int nsplits=1;

  while(batchsize/nsplits*size1*size2*kW*kH*nInputPlane * 4 > freeMem) 
  {
		nsplits *= 2;
  }

  int newbatchsize=batchsize/nsplits;

  THCudaTensor* kernelSlices = THCudaTensor_newWithSize2d(newbatchsize*size1*size2,kW*kH*nInputPlane);

	for(int split=0; split<nsplits; split++)
	{
      sliceInputSplit(input, kernelSlices, kH, kW, dH, dW, padup, paddown, padleft, padright, nsplits, split);
      THCudaTensor* outputsplit = THCudaTensor_newNarrow(output, 0, split*newbatchsize, newbatchsize);
 	   // put output in matrix mode
   	THCudaTensor_resize2d(outputsplit, newbatchsize* size1* size2, nOutputPlane);
		//  printf("sgemm\n");
  		THCudaTensor_addmm(outputsplit, 1,1, kernelSlices, kernels);

	}




  THCudaTensor_free(kernelSlices); 
  THCudaTensor_transpose(kernels, NULL, 0, 1);
//  THCudaTensor_resize4d(kernels, nOutputPlane, kH, kW, nInputPlane);

  // check for errors
  cudaError_t err = cudaGetLastError();
  if (err != cudaSuccess) {
    printf("error in copyPixelsInSlices: %s\n", cudaGetErrorString(err));
    THError("aborting");
  }

  THCudaTensor_resize4d(output, batchsize, size1, size2, nOutputPlane);

  return 1;
}





static int cunxn_SpatialConvolutionUnfold_updateGradInput(lua_State *L)
{
  THCudaTensor *input = (THCudaTensor *)luaT_checkudata(L, 2, "torch.CudaTensor");
  THCudaTensor *gradOutput = (THCudaTensor *)luaT_checkudata(L, 3, "torch.CudaTensor");
  long kW = luaT_getfieldcheckint(L, 1, "kW");
  long kH = luaT_getfieldcheckint(L, 1, "kH");
  long dW = luaT_getfieldcheckint(L, 1, "dW");
  long dH = luaT_getfieldcheckint(L, 1, "dH");
  long padup = luaT_getfieldcheckint(L, 1, "padtop");
  long paddown = luaT_getfieldcheckint(L, 1, "padbottom");
  long padleft = luaT_getfieldcheckint(L, 1, "padleft");
  long padright = luaT_getfieldcheckint(L, 1, "padright");
  long nOutputPlane = luaT_getfieldcheckint(L, 1, "nOutputPlane");
  long nInputPlane = luaT_getfieldcheckint(L, 1, "nInputPlane");

  THCudaTensor *kernels = (THCudaTensor *)luaT_getfieldcheckudata(L, 1, "weight", "torch.CudaTensor");
  THCudaTensor *gradInput = (THCudaTensor *)luaT_getfieldcheckudata(L, 1, "gradInput", "torch.CudaTensor");

  long batchsize = input->size[0];
  long isize1 = input->size[1];
  long isize2 = input->size[2];
  long size1 = gradOutput->size[1];
  long size2 = gradOutput->size[2];

   THCudaTensor_resizeAs(gradInput, input);
	THCudaTensor_fill(gradInput, 0);

  size_t freeMem;
  THCudaCheck(cudaMemGetInfo (&freeMem, NULL));
  int nsplits=1;
  while(batchsize/nsplits*size1*size2*kW*kH*nInputPlane * 4 > freeMem) 
  {
		nsplits *= 2;
  }
  int newbatchsize=batchsize/nsplits;
	THCudaTensor* backwardSlices = THCudaTensor_newWithSize2d(newbatchsize*size1*size2,kW*kH*nInputPlane);


	for(int split=0; split<nsplits; split++)
	{
      THCudaTensor* gradOutputSplit = THCudaTensor_newNarrow(gradOutput, 0, split*newbatchsize, newbatchsize);
      THCudaTensor* gradInputSplit = THCudaTensor_newNarrow(gradInput, 0, split*newbatchsize, newbatchsize);
   	THCudaTensor_resize2d(gradOutputSplit, newbatchsize*size1*size2, nOutputPlane);
		// backprop gradinput into the slices
  	   THCudaTensor_addmm(backwardSlices, 0, 1, gradOutputSplit, kernels);
	   THCudaTensor_resize4d(gradOutputSplit, newbatchsize, size1, size2, nOutputPlane);
	   unsliceGradient(backwardSlices, gradInputSplit, gradOutputSplit, kH, kW, dH, dW, padup, paddown, padleft, padright);
	}


// we resize gradOutput back to what it was...
  THCudaTensor_resize4d(gradOutput, batchsize, size1, size2, nOutputPlane);

	THCudaTensor_free(backwardSlices);

  return 1;
}



static int cunxn_SpatialConvolutionUnfold_accGradParameters(lua_State *L)
{
  THCudaTensor *input = (THCudaTensor *)luaT_checkudata(L, 2, "torch.CudaTensor");
  THCudaTensor *gradOutput = (THCudaTensor *)luaT_checkudata(L, 3, "torch.CudaTensor");
  long kW = luaT_getfieldcheckint(L, 1, "kW");
  long kH = luaT_getfieldcheckint(L, 1, "kH");
  long dW = luaT_getfieldcheckint(L, 1, "dW");
  long dH = luaT_getfieldcheckint(L, 1, "dH");
  long padup = luaT_getfieldcheckint(L, 1, "padtop");
  long paddown = luaT_getfieldcheckint(L, 1, "padbottom");
  long padleft = luaT_getfieldcheckint(L, 1, "padleft");
  long padright = luaT_getfieldcheckint(L, 1, "padright");
  long nOutputPlane = luaT_getfieldcheckint(L, 1, "nOutputPlane");
  long nInputPlane = luaT_getfieldcheckint(L, 1, "nInputPlane");
  long zeroGradients = 0; //luaT_getfieldcheckint(L, 1, "zeroGradients");
  float scale = luaL_optnumber(L, 4, 1);

//  THCudaTensor *kernelSlices = (THCudaTensor *)luaT_getfieldcheckudata(L, 1, "kernelSlices", "torch.CudaTensor");
  // find the size of kernelslices
  long batchsize = gradOutput->size[0];
  long batchstride = gradOutput->stride[0];
  long isize1 = input->size[1];
  long isize2 = input->size[2];
  long size1 = gradOutput->size[1];
  long size2 = gradOutput->size[2];

  THCudaTensor *gradWeight = (THCudaTensor *)luaT_getfieldcheckudata(L, 1, "gradWeight", "torch.CudaTensor");
  THCudaTensor *gradBias = (THCudaTensor *)luaT_getfieldcheckudata(L, 1, "gradBias", "torch.CudaTensor");

//  THCudaTensor_resize2d(gradOutput, batchsize*size1* size2, nOutputPlane);

  float* ptrgradbias = THCudaTensor_data(gradBias);
  float* ptrgradoutput  = THCudaTensor_data(gradOutput);
  dim3 blocksgradbias (nOutputPlane+31/32);
  dim3 threadsgradbias (32,32);

  THCudaTensor_resize2d(gradWeight, nOutputPlane, kW*kH*nInputPlane);



  size_t freeMem;
  THCudaCheck(cudaMemGetInfo (&freeMem, NULL));
  int nsplits=1;
  while(batchsize/nsplits*size1*size2*kW*kH*nInputPlane * 4 > freeMem) 
  {
		nsplits *= 2;
  }
  int newbatchsize=batchsize/nsplits;
  THCudaTensor* kernelSlices = THCudaTensor_newWithSize2d(newbatchsize*size1*size2,kW*kH*nInputPlane);

	for(int split=0; split<nsplits; split++)
	{
      THCudaTensor* gradOutputSplit = THCudaTensor_newNarrow(gradOutput, 0, split*newbatchsize, newbatchsize);
	   THCudaTensor_resize2d(gradOutputSplit, newbatchsize*size1* size2, nOutputPlane);
      THCudaTensor_transpose(gradOutputSplit, NULL, 0, 1);
      THCudaTensor* inputSplit = THCudaTensor_newNarrow(input, 0, split*newbatchsize, newbatchsize);
	   sliceInput(inputSplit, kernelSlices, kH, kW, dH, dW, padup, paddown, padleft, padright);
		THCudaTensor_addmm(gradWeight, 1, scale, gradOutputSplit, kernelSlices); 
	}


	computeGradBias32 <<<blocksgradbias, threadsgradbias>>>  (ptrgradbias, ptrgradoutput, size1, size2, nOutputPlane, scale, batchsize, batchstride);

//  THCudaTensor_transpose(gradOutput, NULL, 0, 1);
//  THCudaTensor_transpose(gradWeight, NULL, 0, 1);

  THCudaTensor_resize4d(gradWeight, nOutputPlane, kH, kW, nInputPlane);

// we resize gradOutput back to what it was...
//  THCudaTensor_resize4d(gradOutput, batchsize, size1, size2, nOutputPlane);
	THCudaTensor_free(kernelSlices);

return 1;

}

static const struct luaL_Reg cunxn_SpatialConvolutionUnfold__ [] = {
  {"SpatialConvolutionUnfold_updateOutput", cunxn_SpatialConvolutionUnfold_updateOutput},
  {"SpatialConvolutionUnfold_updateGradInput", cunxn_SpatialConvolutionUnfold_updateGradInput},
  {"SpatialConvolutionUnfold_accGradParameters", cunxn_SpatialConvolutionUnfold_accGradParameters},
  {NULL, NULL}
};

static void cunxn_SpatialConvolutionUnfold_init(lua_State *L)
{
  luaT_pushmetatable(L, "torch.CudaTensor");
  luaT_registeratname(L, cunxn_SpatialConvolutionUnfold__, "nxn");
  lua_pop(L,1);
}
