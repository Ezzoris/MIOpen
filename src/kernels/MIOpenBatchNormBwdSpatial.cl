/*******************************************************************************
 *
 * MIT License
 *
 * Copyright (c) 2017 Advanced Micro Devices, Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 *******************************************************************************/

#define PPCAT_NX(A, B) A##B
#define PPCAT(A, B) PPCAT_NX(A, B)
#define TWO 2
#define FOUR 4
#define EIGHT 8

#if MIOPEN_USE_FP16 == 1
#pragma OPENCL EXTENSION cl_khr_fp16 : enable
#define _FLOAT half
#ifndef HALF_MAX
#define MAX_VAL 65504 /* max value */
#else
#define MAX_VAL HALF_MAX
#endif
#endif
#if MIOPEN_USE_FP32 == 1
#define _FLOAT float
#ifndef FLT_MAX
#define MAX_VAL 3.402823466e+38F /* max value */
#else
#define MAX_VAL FLT_MAX
#endif
#endif

#define _FLOAT2 PPCAT(_FLOAT, TWO)
#define _FLOAT4 PPCAT(_FLOAT, FOUR)
#define _FLOAT8 PPCAT(_FLOAT, EIGHT)
#define _AS_FLOAT PPCAT(as_, _FLOAT)

#ifndef MIO_BN_LDS_SIZE
#define MIO_BN_LDS_SIZE 1
#endif

#ifndef MIO_BN_LDSGCN_SIZE
#define MIO_BN_LDSGCN_SIZE 16
#endif

#ifndef MIO_BN_C
#define MIO_BN_C 1
#endif

#ifndef MIO_BN_N
#define MIO_BN_N 1
#endif

#ifndef MIO_BN_NHW
#define MIO_BN_NHW 1
#endif

#ifndef MIO_BN_CHW
#define MIO_BN_CHW 1
#endif

#ifndef MIO_BN_INHW
#define MIO_BN_INHW 1
#endif

#ifndef MIO_BN_HW
#define MIO_BN_HW 1
#endif

#ifndef MIO_BN_NCHW
#define MIO_BN_NCHW 1
#endif

#ifndef MIO_BN_GRP0
#define MIO_BN_GRP0 1
#endif

#ifndef MIO_BN_GRP1
#define MIO_BN_GRP1 1
#endif

#ifndef MIO_BN_GRP2
#define MIO_BN_GRP2 1
#endif

#ifndef MIO_BN_NGRPS
#define MIO_BN_NGRPS 1
#endif

#ifndef MIO_BN_VARIANT
#define MIO_BN_VARIANT 0
#endif

#ifndef MIO_BN_NLOOP
#define MIO_BN_NLOOP 1
#endif

#ifndef MIO_BN_USESAVED
#define MIO_BN_USESAVED 1
#endif

#define MIO_BN_MAXN 512

#ifndef MIO_BN_NODPP
#define MIO_BN_NODPP 0
#elif(MIO_BN_NODPP == 1)
#undef __AMDGCN__
#endif

/*
#ifdef __AMDGCN__
#undef __AMDGCN__
#endif
*/

// Disable specific warnings
#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wconditional-uninitialized"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wsometimes-uninitialized"
#endif

#define UNUSED __attribute__((__unused__))

#ifndef __AMDGCN__
static inline void ReduceKernel(__local _FLOAT* lcl_mem,
                                unsigned int sum_stride,
                                unsigned int unit_id,
                                unsigned int unit_len)
{
    _FLOAT sum              = (_FLOAT)0;
    unsigned int lcl_offset = unit_id * unit_len;

#pragma unroll
    for(unsigned int i = 0; i < unit_len; i += sum_stride)
    {
        sum += lcl_mem[lcl_offset + i];
    }
    lcl_mem[lcl_offset] = sum;
}

static inline void
regLDSreduce(_FLOAT* value, __local _FLOAT* data, unsigned int localID, _FLOAT scale)
{
    data[localID] = *value;
    barrier(CLK_LOCAL_MEM_FENCE);
    if(localID < (MIO_BN_LDS_SIZE >> 2))
        ReduceKernel(data, 1, localID, 4);
    barrier(CLK_LOCAL_MEM_FENCE);
    if(localID < (MIO_BN_LDS_SIZE >> 4))
        ReduceKernel(data, 4, localID, 16);
    barrier(CLK_LOCAL_MEM_FENCE);
    if(localID == 0)
        ReduceKernel(data, 16, localID, MIO_BN_LDS_SIZE);
    barrier(CLK_LOCAL_MEM_FENCE);
    *value = data[0] * scale;
}
#endif

#ifdef __AMDGCN__

static inline void dppSimpleRedNoBcast64(_FLOAT* value)
{
    _FLOAT tmp = (_FLOAT)0.;
    *value += _AS_FLOAT(__builtin_amdgcn_mov_dpp(as_int(*value), 0x111, 0xF, 0xF, 0));
    *value += _AS_FLOAT(__builtin_amdgcn_mov_dpp(as_int(*value), 0x112, 0xF, 0xF, 0));
    *value += _AS_FLOAT(__builtin_amdgcn_mov_dpp(as_int(*value), 0x114, 0xF, 0xF, 0));
    *value += _AS_FLOAT(__builtin_amdgcn_mov_dpp(as_int(*value), 0x118, 0xF, 0xF, 0));
    tmp = _AS_FLOAT(__builtin_amdgcn_mov_dpp(as_int(*value), 0x142, 0xF, 0xF, 0));
    *value += tmp;
    tmp = _AS_FLOAT(__builtin_amdgcn_mov_dpp(as_int(*value), 0x143, 0xF, 0xF, 0));
    *value += tmp;
}

static inline void dppSimpleRedBcast64(_FLOAT* value)
{
    _FLOAT tmp = (_FLOAT)0.;
    *value += _AS_FLOAT(__builtin_amdgcn_mov_dpp(as_int(*value), 0x111, 0xF, 0xF, 0));
    *value += _AS_FLOAT(__builtin_amdgcn_mov_dpp(as_int(*value), 0x112, 0xF, 0xF, 0));
    *value += _AS_FLOAT(__builtin_amdgcn_mov_dpp(as_int(*value), 0x114, 0xF, 0xF, 0));
    *value += _AS_FLOAT(__builtin_amdgcn_mov_dpp(as_int(*value), 0x118, 0xF, 0xF, 0));
    tmp = _AS_FLOAT(__builtin_amdgcn_mov_dpp(as_int(*value), 0x142, 0xF, 0xF, 0));
    *value += tmp;
    tmp = _AS_FLOAT(__builtin_amdgcn_mov_dpp(as_int(*value), 0x143, 0xF, 0xF, 0));
    *value += tmp;
    barrier(CLK_LOCAL_MEM_FENCE);
    *value = _AS_FLOAT(__builtin_amdgcn_readlane(as_int(*value), 63));
}

#endif

#if(MIO_BN_VARIANT == 0)

#define MIO_BN_SEGTMP (MIO_BN_HW * (MIO_BN_GRP0 / MIO_BN_HW))
#define MIO_BN_SEGMENT ((MIO_BN_SEGTMP > MIO_BN_NHW) ? (MIO_BN_NHW) : (MIO_BN_SEGTMP))
#define MIO_BN_NLOOP ((MIO_BN_NHW + MIO_BN_SEGMENT - 1) / MIO_BN_SEGMENT)
#define MIO_BN_SEGIHW (MIO_BN_SEGMENT / MIO_BN_HW)
#define MIO_BN_NLOOPM (MIO_BN_NLOOP - 1)
#define MIO_BN_SNHW (MIO_BN_NLOOPM * MIO_BN_SEGIHW)

__attribute__((reqd_work_group_size(MIO_BN_GRP0, MIO_BN_GRP1, MIO_BN_GRP2))) __kernel void
BatchNormBwdSpatial(const __global _FLOAT* __restrict x_in,
                    const __global _FLOAT* __restrict dy_in,
                    __global _FLOAT* __restrict dx_out,
                    const __global _FLOAT* bnScale,
                    __global _FLOAT* __restrict dscale,
                    __global _FLOAT* __restrict dbias,
#if(MIO_BN_USESAVED == 0)
                    double epsilon,
#elif(MIO_BN_USESAVED == 1)
                    const __global _FLOAT* savedMean,
                    const __global _FLOAT* savedInvVariance,
#endif
                    _FLOAT INHW)
{

    // SPATIAL
    _FLOAT mean = (_FLOAT)0.;
#if(MIO_BN_USESAVED == 0)
    _FLOAT variance = (_FLOAT)0.;
#endif
    _FLOAT invVariance = (_FLOAT)0.;
    _FLOAT pscale      = (_FLOAT)0.;
    _FLOAT ds          = (_FLOAT)0.;
    _FLOAT db          = (_FLOAT)0.;

    _FLOAT batchvalues[MIO_BN_NLOOP];
    _FLOAT dyvalues[MIO_BN_NLOOP];

    __local _FLOAT lbns;
    __local _FLOAT lcl_data[MIO_BN_LDS_SIZE];
#if(MIO_BN_USESAVED == 1)
    __local _FLOAT lmean, lvar;
#endif
    unsigned int index  = 0;
    unsigned int lid    = get_local_id(0);
    unsigned int grpid  = get_group_id(0);
    unsigned int chwid  = grpid * MIO_BN_HW + (lid % MIO_BN_HW);
    unsigned int lidihw = lid / MIO_BN_HW;
    unsigned int nid    = 0;
    _FLOAT tmp1, tmp2, tmp3;

    _FLOAT NHW = (_FLOAT)MIO_BN_NHW;

    if(lid == 0)
    {
        lbns = *(bnScale + grpid);

#if(MIO_BN_USESAVED == 1)
        lmean = *(savedMean + grpid);
        lvar  = *(savedInvVariance + grpid);
    }
    barrier(CLK_LOCAL_MEM_FENCE);
    mean        = lmean;
    invVariance = lvar;
#else // recalc mean and variance below
    } // end if(!lid)

    // == RECALC MEAN AND VARIANCE ===========
    if(lid < MIO_BN_SEGMENT)
    {
#pragma unroll
        for(unsigned int n = 0; n < MIO_BN_NLOOPM; ++n)
        {
            nid            = n * MIO_BN_SEGIHW + lidihw;
            index          = nid * MIO_BN_CHW + chwid;
            batchvalues[n] = *(in + index);
            mean += batchvalues[n];
            variance = mad(batchvalues[n], batchvalues[n], variance);
        }
        nid                        = MIO_BN_SNHW + lidihw;
        index                      = nid * MIO_BN_CHW + chwid;
        batchvalues[MIO_BN_NLOOPM] = (index < MIO_BN_NCHW) ? *(in + index) : (_FLOAT)0.;
        mean += batchvalues[MIO_BN_NLOOPM];
        variance = mad(batchvalues[MIO_BN_NLOOPM], batchvalues[MIO_BN_NLOOPM], variance);
    }

#ifndef __AMDGCN__
    __local _FLOAT lcl_data[MIO_BN_LDS_SIZE];

    // Reduce mean
    lcl_data[lid] = mean;
    barrier(CLK_LOCAL_MEM_FENCE);
    for(unsigned int red = (MIO_BN_GRP0 >> 1); red > 256; red >>= 1)
    {
        if(lid < red)
            lcl_data[lid] += lcl_data[lid + red];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    regLDSreduce(&mean, lcl_data, lid, (_FLOAT)INHW);
    barrier(CLK_LOCAL_MEM_FENCE);

    // Reduce variance
    lcl_data[lid] = variance;
    barrier(CLK_LOCAL_MEM_FENCE);
    for(unsigned int red = (MIO_BN_GRP0 >> 1); red > 256; red >>= 1)
    {
        if(lid < red)
            lcl_data[lid] += lcl_data[lid + red];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    regLDSreduce(&variance, lcl_data, lid, (_FLOAT)INHW);
    barrier(CLK_LOCAL_MEM_FENCE);
#else

    unsigned int ldsidx = lid >> 6;
    __local _FLOAT lcl_mean[MIO_BN_LDSGCN_SIZE];
    __local _FLOAT lcl_variance[MIO_BN_LDSGCN_SIZE];

    dppSimpleRedNoBcast64(&mean);
    dppSimpleRedNoBcast64(&variance);

    if((lid % 64) == 63)
    {
        lcl_mean[ldsidx]     = mean;
        lcl_variance[ldsidx] = variance;
    }
    barrier(CLK_LOCAL_MEM_FENCE);
    mean = variance = 0.;

#pragma unroll
    for(uint i = 0; i < MIO_BN_LDSGCN_SIZE; i++)
    {
        mean += lcl_mean[i];
        variance += lcl_variance[i];
    }
    mean *= (_FLOAT)INHW;
    variance *= (_FLOAT)INHW;

#endif

    variance               = mad(-mean, mean, variance);
    invVariance            = rsqrt(variance + epsilon);
#endif // end -- Recalc mean and variance
    //-------------------------------------------

    //==== CALC DB and DS =========================================
    if(lid < MIO_BN_SEGMENT)
    {
#pragma unroll
        for(unsigned int n = 0; n < MIO_BN_NLOOPM; ++n)
        {
            nid         = n * MIO_BN_SEGIHW + lidihw;
            index       = nid * MIO_BN_CHW + chwid;
            dyvalues[n] = *(dy_in + index);
            db += dyvalues[n];

#if(MIO_BN_USESAVED == 1)
            batchvalues[n] = (*(x_in + index) - mean) * invVariance;
#else
            batchvalues[n] = (batchvalues[n] - mean) * invVariance;
#endif
            // batchvalues is now xhat
            ds = mad(batchvalues[n], dyvalues[n], ds);
        }
        nid                     = MIO_BN_SNHW + lidihw;
        index                   = nid * MIO_BN_CHW + chwid;
        dyvalues[MIO_BN_NLOOPM] = ((index < MIO_BN_NCHW) ? *(dy_in + index) : (_FLOAT)0.);
        db += dyvalues[MIO_BN_NLOOPM];

#if(MIO_BN_USESAVED == 1)
        batchvalues[MIO_BN_NLOOPM] =
            (((index < MIO_BN_NCHW) ? *(x_in + index) : (_FLOAT)0.) - mean) * invVariance;
#else
        batchvalues[MIO_BN_NLOOPM] = (batchvalues[MIO_BN_NLOOPM] - mean) * invVariance;
#endif
        // batchvalues is now xhat
        ds = mad(batchvalues[MIO_BN_NLOOPM], dyvalues[MIO_BN_NLOOPM], ds);

#ifndef __AMDGCN__
        __local _FLOAT lcl_data[MIO_BN_LDS_SIZE];
        lcl_data[lid] = ds;
        barrier(CLK_LOCAL_MEM_FENCE);
        for(unsigned int red = (MIO_BN_GRP0 >> 1); red > 256; red >>= 1)
        {
            if(lid < red)
                lcl_data[lid] += lcl_data[lid + red];
            barrier(CLK_LOCAL_MEM_FENCE);
        }
        regLDSreduce(&ds, lcl_data, lid, (_FLOAT)1.0);
        barrier(CLK_LOCAL_MEM_FENCE);

        lcl_data[lid] = db;
        barrier(CLK_LOCAL_MEM_FENCE);
        for(unsigned int red = (MIO_BN_GRP0 >> 1); red > 256; red >>= 1)
        {
            if(lid < red)
                lcl_data[lid] += lcl_data[lid + red];
            barrier(CLK_LOCAL_MEM_FENCE);
        }
        regLDSreduce(&db, lcl_data, lid, (_FLOAT)1.0);
        barrier(CLK_LOCAL_MEM_FENCE);
#else
        unsigned int ldsidx = lid >> 6;
        __local _FLOAT lcl_ds[MIO_BN_LDSGCN_SIZE];
        __local _FLOAT lcl_db[MIO_BN_LDSGCN_SIZE];

        dppSimpleRedNoBcast64(&ds);
        dppSimpleRedNoBcast64(&db);

        if((lid % 64) == 63)
        {
            lcl_ds[ldsidx] = ds;
            lcl_db[ldsidx] = db;
        }
        barrier(CLK_LOCAL_MEM_FENCE);
        ds = db = 0.;
#pragma unroll
        for(uint i = 0; i < MIO_BN_LDSGCN_SIZE; i++)
        {
            ds += lcl_ds[i];
            db += lcl_db[i];
        }
#endif

        if(lid < MIO_BN_SEGMENT)
        {
            //==== CALC NORM =======================
            _FLOAT inhat = 0.;
            pscale       = lbns;
#pragma unroll
            for(unsigned int n = 0; n < MIO_BN_NLOOPM; n++)
            { // apply normalization
                nid           = n * MIO_BN_SEGIHW + lidihw;
                index         = nid * MIO_BN_CHW + chwid;
                tmp1          = mad(NHW, dyvalues[n], -db);
                tmp2          = -batchvalues[n] * ds;
                tmp3          = (pscale * invVariance) * INHW;
                dx_out[index] = tmp3 * (tmp2 + tmp1);
            } // end for
            nid   = MIO_BN_SNHW + lidihw;
            index = nid * MIO_BN_CHW + chwid;
            if(index < MIO_BN_NCHW)
            {
                tmp1          = mad(NHW, dyvalues[MIO_BN_NLOOPM], -db);
                tmp2          = -batchvalues[MIO_BN_NLOOPM] * ds;
                tmp3          = (pscale * invVariance) * INHW;
                dx_out[index] = tmp3 * (tmp2 + tmp1);
            }
        }
        if(lid == 0)
        {
            dbias[grpid]  = db;
            dscale[grpid] = ds;
        }
    } // end spatial

#elif(MIO_BN_VARIANT == 1)

#define MIO_BN_REM (MIO_BN_NHW - ((MIO_BN_NHW / MIO_BN_GRP0) * MIO_BN_GRP0))
#define MIO_BN_LESS (MIO_BN_NHW - MIO_BN_REM)

__attribute__((reqd_work_group_size(MIO_BN_GRP0, MIO_BN_GRP1, MIO_BN_GRP2))) __kernel void
BatchNormBwdSpatial(const __global _FLOAT* __restrict x_in,
                    const __global _FLOAT* __restrict dy_in,
                    __global _FLOAT* __restrict dx_out,
                    const __global _FLOAT* bnScale,
                    __global _FLOAT* __restrict dscale,
                    __global _FLOAT* __restrict dbias,
#if(MIO_BN_USESAVED == 0)
                    double epsilon,
#elif(MIO_BN_USESAVED == 1)
                    const __global _FLOAT* savedMean,
                    const __global _FLOAT* savedInvVariance,
#endif
                    _FLOAT INHW)
{

    // SPATIAL
    _FLOAT mean        = (_FLOAT)0.;
    _FLOAT invVariance = (_FLOAT)0.;
    _FLOAT pscale      = (_FLOAT)0.;
    _FLOAT db          = (_FLOAT)0.;
    _FLOAT ds          = (_FLOAT)0.;
    _FLOAT xhat        = (_FLOAT)0.;

#if(MIO_BN_USESAVED == 1)
    __local _FLOAT lmean, lvar;
#endif

    __local _FLOAT lcl_scale;

#if(MIO_BN_NHW < MIO_BN_MAXN)
    _FLOAT input[MIO_BN_NHW];
    _FLOAT dyvalues[MIO_BN_NHW];
#endif

    _FLOAT NHW = (_FLOAT)MIO_BN_NHW;

    unsigned int index = 0;
    unsigned int lid   = get_local_id(1);
    unsigned int xgid  = get_global_id(0);
    unsigned int grpid = get_group_id(0);
    unsigned int chwid = grpid * MIO_BN_HW;
    unsigned int nidx  = 0;
    unsigned int hwidx = 0;

    if(lid == 0)
    {
        lcl_scale = *(bnScale + xgid);
#if(MIO_BN_USESAVED == 1)
        lmean     = *(savedMean + gxgid);
        lvar      = *(savedInvVariance + xgid);
#endif
    }
    barrier(CLK_LOCAL_MEM_FENCE);

#if(MIO_BN_USESAVED == 0)
    //==== CALC MEAN and VARIANCE ONCE AGAIN =======================
    _FLOAT variance = (_FLOAT)0.;
#pragma unroll
    for(unsigned int k = lid, lesskey = 0; k < MIO_BN_LESS; k += MIO_BN_GRP1, ++lesskey)
    {
        nidx           = k / MIO_BN_HW;
        hwidx          = k - (nidx * MIO_BN_HW);
        index          = nidx * MIO_BN_CHW + chwid + hwidx;
#if(MIO_BN_NHW < MIO_BN_MAXN)
        input[lesskey] = *(x_in + index);
        mean += input[lesskey];
        variance = mad(input[lesskey], input[lesskey], variance);
#else
        _FLOAT in = *(x_in + index);
        mean += in;
        variance        = mad(in, in, variance);
#endif
    }
#if(MIO_BN_REM)
    unsigned int remkey = lid + MIO_BN_LESS;
    nidx                = remkey / MIO_BN_HW;
    hwidx               = remkey - (nidx * MIO_BN_HW);
    index               = nidx * MIO_BN_CHW + chwid + hwidx;
#if(MIO_BN_NHW < MIO_BN_MAXN)
    input[remkey]       = (index < MIO_BN_NCHW) ? *(x_in + index) : 0.;
    mean += input[remkey];
    variance = mad(input[remkey], input[remkey], variance);
#else
    _FLOAT in = (index < MIO_BN_NCHW) ? *(x_in + index) : 0.;
    mean += in;
    variance = mad(xin, xin, variance);
#endif
#endif

// REDUCE MEAN AND VARIANCE -----------------------
#ifndef __AMDGCN__
    local _FLOAT lcl_data[MIO_BN_LDS_SIZE];
    lcl_data[lid] = mean;
    barrier(CLK_LOCAL_MEM_FENCE);

    for(unsigned int red = (MIO_BN_GRP1 >> 1); red > 256; red >>= 1)
    {
        if(lid < red)
            lcl_data[lid] += lcl_data[lid + red];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    regLDSreduce(&mean, lcl_data, lid, (_FLOAT)INHW);

    barrier(CLK_LOCAL_MEM_FENCE);
    lcl_data[lid] = variance;
    barrier(CLK_LOCAL_MEM_FENCE);

    for(unsigned int red = (MIO_BN_GRP1 >> 1); red > 256; red >>= 1)
    {
        if(lid < red)
            lcl_data[lid] += lcl_data[lid + red];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    regLDSreduce(&variance, lcl_data, lid, (_FLOAT)INHW);
    barrier(CLK_LOCAL_MEM_FENCE);

#else
    unsigned int ldsidx = lid >> 6;
    __local _FLOAT lcl_mean[MIO_BN_LDSGCN_SIZE];
    __local _FLOAT lcl_variance[MIO_BN_LDSGCN_SIZE];

    dppSimpleRedNoBcast64(&mean);
    dppSimpleRedNoBcast64(&variance);
    if((lid % 64) == 63)
    {
        lcl_mean[ldsidx]     = mean;
        lcl_variance[ldsidx] = variance;
    }
    barrier(CLK_LOCAL_MEM_FENCE);
    mean = variance = 0.;
#pragma unroll
    for(uint i = 0; i < MIO_BN_LDSGCN_SIZE; i++)
    {
        mean += lcl_mean[i];
        variance += lcl_variance[i];
    }
    mean *= (_FLOAT)INHW;
    variance *= (_FLOAT)INHW;
#endif
    // REDUCTION COMPLETE ---------------------------

    variance    = mad(-mean, mean, variance);
    invVariance = rsqrt(variance + epsilon);

// RECALC of MEAN and VARIANCE complete
//===============================================

#else // MIO_BN_USESAVED == 1

    mean               = lmean;
    invVariance        = lvar;

#endif

#pragma unroll
    for(unsigned int k = lid, lesskey = 0; k < MIO_BN_LESS; k += MIO_BN_GRP1, ++lesskey)
    {
        nidx              = k / MIO_BN_HW;
        hwidx             = k - (nidx * MIO_BN_HW);
        index             = nidx * MIO_BN_CHW + chwid + hwidx;
#if(MIO_BN_NHW < MIO_BN_MAXN)
        dyvalues[lesskey] = *(dy_in + index);
        xhat              = (input[lesskey] - mean) * invVariance;
        db += dyvalues[lesskey];
        ds = mad(xhat, dyvalues[lesskey], ds);
#else
        _FLOAT dyvalue = *(dy_in + index);
        xhat           = (*(x_in + index) - mean) * invVariance;
        db += dyvalue;
        ds              = mad(xhat, dyvalue, ds);
#endif
    }

#if(MIO_BN_REM)
#if(MIO_BN_USESAVED == 1)
    unsigned int remkey = 0;
#endif
    remkey              = lid + MIO_BN_LESS;
    nidx                = remkey / MIO_BN_HW;
    hwidx               = remkey - (nidx * MIO_BN_HW);
    index               = nidx * MIO_BN_CHW + chwid + hwidx;
    if(index < MIO_BN_NCHW)
    {
#if(MIO_BN_NHW < MIO_BN_MAXN)
        dyvalues[remkey] = *(dy_in + index);
        xhat             = (input[remkey] - mean) * invVariance;
        db += dyvalues[remkey];
        ds = mad(xhat, dyvalues[remkey], ds);
#else
        _FLOAT dyvalue = *(dy_in + index);
        xhat           = (*(x_in + index) - mean) * invVariance;
        db += dyvalue;
        ds             = mad(xhat, dyvalue, ds);
#endif
    }
#endif

#ifndef __AMDGCN__
    __local _FLOAT lcl_data[MIO_BN_LDS_SIZE];
    lcl_data[lid] = ds;
    barrier(CLK_LOCAL_MEM_FENCE);
    for(unsigned int red = (MIO_BN_GRP0 >> 1); red > 256; red >>= 1)
    {
        if(lid < red)
            lcl_data[lid] += lcl_data[lid + red];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    regLDSreduce(&ds, lcl_data, lid, (_FLOAT)1.0);
    barrier(CLK_LOCAL_MEM_FENCE);

    lcl_data[lid] = db;
    barrier(CLK_LOCAL_MEM_FENCE);
    for(unsigned int red = (MIO_BN_GRP0 >> 1); red > 256; red >>= 1)
    {
        if(lid < red)
            lcl_data[lid] += lcl_data[lid + red];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    regLDSreduce(&db, lcl_data, lid, (_FLOAT)1.0);
    barrier(CLK_LOCAL_MEM_FENCE);
#else
    unsigned int ldsidx = lid >> 6;
    __local _FLOAT lcl_ds[MIO_BN_LDSGCN_SIZE];
    __local _FLOAT lcl_db[MIO_BN_LDSGCN_SIZE];

    dppSimpleRedNoBcast64(&ds);
    dppSimpleRedNoBcast64(&db);

    if((lid % 64) == 63)
    {
        lcl_ds[ldsidx] = ds;
        lcl_db[ldsidx] = db;
    }
    barrier(CLK_LOCAL_MEM_FENCE);
    ds = db = 0.;
#pragma unroll
    for(uint i = 0; i < MIO_BN_LDSGCN_SIZE; i++)
    {
        ds += lcl_ds[i];
        db += lcl_db[i];
    }
#endif

    pscale = lcl_scale;

    _FLOAT tmp1 = 0.;
    _FLOAT tmp2 = 0.;
    _FLOAT tmp3 = 0.;
#pragma unroll
    for(unsigned int k = lid, lesskey = 0; k < MIO_BN_LESS; k += MIO_BN_GRP1, ++lesskey)
    {
        nidx              = k / MIO_BN_HW;
        hwidx             = k - (nidx * MIO_BN_HW);
        index             = nidx * MIO_BN_CHW + chwid + hwidx;
#if(MIO_BN_NHW < MIO_BN_MAXN)
        xhat              = (input[lesskey] - mean) * invVariance;
        tmp1              = mad(NHW, dyvalues[lesskey], -db);
        tmp2              = -xhat * ds;
        tmp3              = pscale * invVariance * INHW;
#else
        _FLOAT dyvalue = *(dy_in + index);
        xhat           = (*(x_in + index) - mean) * invVariance;
        tmp1           = mad(NHW, dyvalue, -db);
        tmp2           = -xhat * ds;
        tmp3           = pscale * invVariance * INHW;
#endif
        *(dx_out + index) = tmp3 * (tmp2 + tmp1);
    }

#if(MIO_BN_REM)
    nidx  = remkey / MIO_BN_HW;
    hwidx = remkey - (nidx * MIO_BN_HW);
    index = nidx * MIO_BN_CHW + chwid + hwidx;
    if(index < MIO_BN_NCHW)
    {
#if(MIO_BN_NHW < MIO_BN_MAXN)
        xhat              = (input[remkey] - mean) * invVariance;
        tmp1              = mad(NHW, dyvalues[remkey], -db);
        tmp2              = -xhat * ds;
        tmp3              = pscale * invVariance * INHW;
#else
        _FLOAT dyvalue = *(dy_in + index);
        xhat           = (*(x_in + index) - mean) * invVariance;
        tmp1           = mad(NHW, dyvalue, -db);
        tmp2           = -xhat * ds;
        tmp3           = pscale * invVariance * INHW;
#endif
        *(dx_out + index) = tmp3 * (tmp2 + tmp1);
    }
#endif

    if(lid == 0)
    {
        *(dbias + grpid)  = db;
        *(dscale + grpid) = ds;
    }
}

#elif(MIO_BN_VARIANT == 2)

#if(MIO_BN_USESAVED == 0)

__attribute__((reqd_work_group_size(MIO_BN_GRP0, MIO_BN_GRP1, MIO_BN_GRP2))) __kernel void
BatchNormBwdSpatialFinalMeanVariance(__global _FLOAT* __restrict meanvarbuff,
                                     _FLOAT INHW,
                                     double epsilon)
{
    _FLOAT variance             = (_FLOAT)0.;
    _FLOAT invVariance          = (_FLOAT)0.;
    _FLOAT mean                 = (_FLOAT)0.;
    unsigned int lid            = get_local_id(1);
    unsigned int ygrp_id        = get_group_id(1);
    unsigned int xgid           = get_global_id(0);
    unsigned int ygrp_sz        = get_local_size(1);
    unsigned int yngrps         = get_num_groups(1);
    unsigned int cidx           = xgid * MIO_BN_HW;
    unsigned int meanstashindex = cidx + ygrp_sz * ygrp_id + 1;
    unsigned int varstashindex  = cidx + ygrp_sz * ygrp_id + 3;
    unsigned int commitID       = 0;

    for(int gn = 0; gn < yngrps; gn++)
    {
        unsigned int offset    = gn * ygrp_sz + lid;
        unsigned int meanindex = cidx + ygrp_sz * offset;
        unsigned int varindex  = cidx + ygrp_sz * offset + 2;
        if(offset < yngrps)
        { // modify to span larger number of groups
            mean += *(meanvarbuff + meanindex);
            variance += *(meanvarbuff + varindex); // load per group variance
        }
    }


    __local _FLOAT lcl_data[MIO_BN_NGRPS];
    lcl_data[lid] = mean;
    barrier(CLK_LOCAL_MEM_FENCE);

#if(MIO_BN_NGRPS > 256)
    for(unsigned int red = (MIO_BN_GRP1 >> 1); red > 256; red >>= 1)
    {
        if(lid < red)
            lcl_data[lid] += lcl_data[lid + red];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    regLDSreduce(&mean, lcl_data, lid, (_FLOAT)INHW);
#elif(MIO_BN_NGRPS <= 256)
    regLDSreduce(&mean, lcl_data, lid, (_FLOAT)INHW);
    commitID = 0;
#else
    mean = (_FLOAT)0.;
#pragma unroll
    for(int i = 0; i < MIO_BN_NGRPS; i++)
    {
        mean += lcl_data[i];
    }

#endif

    lcl_data[lid] = variance;
    barrier(CLK_LOCAL_MEM_FENCE);

#if(MIO_BN_NGRPS > 256)
    for(unsigned int red = (MIO_BN_GRP1 >> 1); red > 256; red >>= 1)
    {
        if(lid < red)
            lcl_data[lid] += lcl_data[lid + red];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    regLDSreduce(&variance, lcl_data, lid, (_FLOAT)INHW);
#elif(MIO_BN_NGRPS <= 256)
    regLDSreduce(&variance, lcl_data, lid, (_FLOAT)INHW);
#else //(MIO_BN_NGRPS <= 16)
    variance = (_FLOAT)0.;
#pragma unroll
    for(int i = 0; i < MIO_BN_NGRPS; i++)
    {
        variance += lcl_data[i];
    }
#endif

    invVariance = rsqrt(variance + epsilon);
    if(lid == commitID)
    {
        meanvarbuff[meanstashindex] = mean;        // stash mean
        meanvarbuff[varstashindex]  = invVariance; // stash mean
    }
}



__attribute__((reqd_work_group_size(MIO_BN_GRP0, MIO_BN_GRP1, MIO_BN_GRP2))) __kernel void
BatchNormBwdSpatialMeanVariance(const __global _FLOAT* __restrict in,
                                __global _FLOAT* __restrict mvbuff)
{

    unsigned int ylid    = get_local_id(1);
    unsigned int ygrp_id = get_group_id(1);
    unsigned int xgid    = get_global_id(0);
    unsigned int ygid    = get_global_id(1);
    unsigned int ygrp_sz = get_local_size(1);
    unsigned int index;
    unsigned int cidx      = xgid * MIO_BN_HW;
    unsigned int meanindex = cidx + ygrp_sz * ygrp_id;
    unsigned int varindex  = meanindex + 2;
    _FLOAT mean            = (_FLOAT)0.;
    _FLOAT variance        = (_FLOAT)0.;
    _FLOAT value           = (_FLOAT)0.;

    if(ygid < MIO_BN_HW)
    {
#pragma unroll
        for(unsigned int n = 0; n < MIO_BN_N; n++)
        {
            index = n * MIO_BN_CHW + cidx + ygid;
            value = *(in + index);
            mean += value;
            variance = mad(value, value, variance);
        }
    }

#ifdef __AMDGCN__
    unsigned int ldsidx = ylid >> 6;
    __local _FLOAT lcl_mean[MIO_BN_LDSGCN_SIZE];
    __local _FLOAT lcl_variance[MIO_BN_LDSGCN_SIZE];

    dppSimpleRedNoBcast64(&mean);
    dppSimpleRedNoBcast64(&variance);

    if((ylid % 64) == 63)
    {
        lcl_mean[ldsidx]     = mean;
        lcl_variance[ldsidx] = variance;
    }
    barrier(CLK_LOCAL_MEM_FENCE | CLK_GLOBAL_MEM_FENCE);
    mean = variance = 0.;

#pragma unroll
    for(uint i = 0; i < MIO_BN_LDSGCN_SIZE; i++)
    {
        mean += lcl_mean[i];
        variance += lcl_variance[i];
    }

#else
    __local _FLOAT lcl_data[MIO_BN_LDS_SIZE];
    lcl_data[ylid] = mean;
    barrier(CLK_LOCAL_MEM_FENCE);

    for(unsigned int red = (MIO_BN_GRP1 >> 1); red > 256; red >>= 1)
    {
        if(ylid < red)
            lcl_data[ylid] += lcl_data[ylid + red];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    regLDSreduce(&mean, lcl_data, ylid, 1);
    barrier(CLK_LOCAL_MEM_FENCE);

    lcl_data[ylid] = variance;
    barrier(CLK_LOCAL_MEM_FENCE);

    for(unsigned int red = (MIO_BN_GRP1 >> 1); red > 256; red >>= 1)
    {
        if(ylid < red)
            lcl_data[ylid] += lcl_data[ylid + red];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    regLDSreduce(&variance, lcl_data, ylid, 1);
    barrier(CLK_LOCAL_MEM_FENCE);
#endif

    if(ylid == 0)
    {
        mvbuff[meanindex] = mean;
        mvbuff[varindex]  = variance;
    }
} // end spatial mean kernel

#endif // end USESAVED == 0




__attribute__((reqd_work_group_size(MIO_BN_GRP0, MIO_BN_GRP1, MIO_BN_GRP2))) __kernel void
BatchNormBwdSpatialDScaleDBias(const __global _FLOAT* x_in,
                          const __global _FLOAT* dy_in,
                          __global _FLOAT* buff
#if(MIO_BN_USESAVED == 1)

                          ,
                          const __global _FLOAT* savedMean,
                          const __global _FLOAT* savedInvVariance
#endif
                          )
{

    __local _FLOAT lcl_data[MIO_BN_LDS_SIZE];

    unsigned int xgid    = get_global_id(0);
    unsigned int ylid    = get_local_id(1);
    unsigned int ygrp_id = get_group_id(1);
    unsigned int ygid    = get_global_id(1);
    unsigned int ygrp_sz = get_local_size(1);
    unsigned int index;
    unsigned int cidx = xgid * MIO_BN_HW;
    
    _FLOAT mean    = (_FLOAT)0.;
    _FLOAT invVar  = (_FLOAT)0.;
    _FLOAT elemStd = (_FLOAT)0.;
    _FLOAT xhat    = (_FLOAT)0.;
    _FLOAT dscale  = (_FLOAT)0.;
    _FLOAT dbias      = (_FLOAT)0.;

    __local _FLOAT lmean, livar;

    if(ylid == 0)
    {
#if(MIO_BN_USESAVED == 0)
        unsigned int meanstashindex = cidx + ygrp_sz * ygrp_id + 1;
        unsigned int varstashindex  = cidx + ygrp_sz * ygrp_id + 3;
        lmean                       = *(buff + meanstashindex); // load stashed mean
        livar                       = *(buff + varstashindex);
#else  // NO SAVED
        lmean = *(savedMean+xgid);
        livar = *(savedInvVariance+xgid);
#endif // SAVED
    }
    barrier(CLK_LOCAL_MEM_FENCE);


    if(ygid < MIO_BN_HW)
    {
        mean   = lmean;
        invVar = livar;
#pragma unroll
        for(unsigned int n = 0; n < MIO_BN_N; n++)
        {
            index = n * MIO_BN_CHW + cidx + ygid;
            dbias += *(dy_in + index);
            elemStd = *(x_in + index) - mean; 
            xhat    = elemStd * invVar;
            dscale  = mad(xhat, dy_in[index], dscale);
        }
    }

    //REDUCE over DS and DB

#ifdef __AMDGCN__
    unsigned int ldsidx = ylid >> 6;
    __local _FLOAT lcl_db[MIO_BN_LDSGCN_SIZE];
    __local _FLOAT lcl_ds[MIO_BN_LDSGCN_SIZE];

    dppSimpleRedNoBcast64(&dbias);
    dppSimpleRedNoBcast64(&dscale);

    if((ylid % 64) == 63)
    {
        lcl_db[ldsidx] = dbias;
        lcl_ds[ldsidx] = dscale;
    }
    barrier(CLK_LOCAL_MEM_FENCE | CLK_GLOBAL_MEM_FENCE);
    dbias = dscale = 0.;

#pragma unroll
    for(uint i = 0; i < MIO_BN_LDSGCN_SIZE; i++)
    {
        dbias  += lcl_db[i];
        dscale += lcl_ds[i];
    }

#else
    lcl_data[ylid] = dbias;
    barrier(CLK_LOCAL_MEM_FENCE);

    for(unsigned int red = (MIO_BN_GRP1 >> 1); red > 256; red >>= 1)
    {
        if(ylid < red)
            lcl_data[ylid] += lcl_data[ylid + red];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    regLDSreduce(&dbias, lcl_data, ylid, 1);
    barrier(CLK_LOCAL_MEM_FENCE);

    lcl_data[ylid] = dscale;
    barrier(CLK_LOCAL_MEM_FENCE);

    for(unsigned int red = (MIO_BN_GRP1 >> 1); red > 256; red >>= 1)
    {
        if(ylid < red)
            lcl_data[ylid] += lcl_data[ylid + red];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    regLDSreduce(&dscale, lcl_data, ylid, 1);
    barrier(CLK_LOCAL_MEM_FENCE);
#endif

    // end reduction-----------


    if(ylid == 0)
    {
        unsigned int betaindex = cidx + ygrp_sz * ygrp_id + 6;
        unsigned int gammaindex = cidx + ygrp_sz * ygrp_id + 4;
        buff[gammaindex] = dscale;
        buff[betaindex]  = dbias;
    }
}





__attribute__((reqd_work_group_size(MIO_BN_GRP0, MIO_BN_GRP1, MIO_BN_GRP2))) __kernel void
BatchNormBwdSpatialFinalDScaleDBias(__global _FLOAT* buff, __global _FLOAT* delta_scale, __global _FLOAT* delta_bias)
{


    __local _FLOAT lcl_data[MIO_BN_NGRPS];
    _FLOAT ds = (_FLOAT)0.;
    _FLOAT db = (_FLOAT)0.;

    unsigned int ylid    = get_local_id(1);
    unsigned int xgid    = get_global_id(0);
    unsigned int ygid    = get_global_id(1);
    unsigned int ygrp_sz = get_local_size(1);
    unsigned int yngrps  = get_num_groups(1);
    int cidx             = MIO_BN_HW * xgid;

#pragma unroll
    for(int gn = 0; gn < MIO_BN_NGRPS; gn++)
    {
        unsigned int offset = gn * ygrp_sz + ylid;
        if(offset < yngrps)
        { // modify to span larger number of groups
            unsigned int gammaindex = cidx + ygrp_sz * offset + 4;
            unsigned int betaindex = cidx + ygrp_sz * offset + 6;
            ds += *(buff + gammaindex);
            db += *(buff + betaindex);
        }
    }
    lcl_data[lid] = ds;
    barrier(CLK_LOCAL_MEM_FENCE);

#if(MIO_BN_NGRPS > 256)
    for(unsigned int red = (MIO_BN_GRP1 >> 1); red > 256; red >>= 1)
    {
        if(lid < red)
            lcl_data[lid] += lcl_data[lid + red];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    regLDSreduce(&ds, lcl_data, lid, 1.);
#elif(MIO_BN_NGRPS <= 256)
    regLDSreduce(&ds, lcl_data, lid, 1.);
    commitID = 0;
#else
    ds = (_FLOAT)0.;
#pragma unroll
    for(int i = 0; i < MIO_BN_NGRPS; i++)
    {
        ds += lcl_data[i];
    }

#endif

    lcl_data[lid] = db;
    barrier(CLK_LOCAL_MEM_FENCE);

#if(MIO_BN_NGRPS > 256)
    for(unsigned int red = (MIO_BN_GRP1 >> 1); red > 256; red >>= 1)
    {
        if(lid < red)
            lcl_data[lid] += lcl_data[lid + red];
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    regLDSreduce(&db, lcl_data, lid, 1.);
#elif(MIO_BN_NGRPS <= 256)
    regLDSreduce(&db, lcl_data, lid, 1.);
#else //(MIO_BN_NGRPS <= 16)
    db = (_FLOAT)0.;
#pragma unroll
    for(int i = 0; i < MIO_BN_NGRPS; i++)
    {
        db += lcl_data[i];
    }
#endif

    if(ygid == 0){
        delta_scale[xgid] = ds;
        delta_bias[xgid]  = db;
    }
}





__attribute__((reqd_work_group_size(MIO_BN_GRP0, MIO_BN_GRP1, MIO_BN_GRP2))) __kernel void
BatchNormBwdSpatialDX(const __global _FLOAT* x_in,
                      const __global _FLOAT* dy_in,
                      __global _FLOAT* dx_out,
                      const __global _FLOAT* bnScale,
                      __global _FLOAT* delta_scale,
                      __global _FLOAT* delta_bias,
#if(MIO_BN_USESAVED == 1)
                      const __global _FLOAT* savedMean,
                      const __global _FLOAT* savedInvVariance,
#endif
                      _FLOAT INHW)
{

    int xgid = get_global_id(0);
    int ygid = get_global_id(1);
    int cidx = MIO_BN_HW * xgid;
    unsigned int index;
    _FLOAT mean, invVar;
    _FLOAT elemStd, xhat;
    _FLOAT scale, dscale, dbias;
    _FLOAT tmp1, tmp2, tmp3;
    _FLOAT NHW = (_FLOAT)MIO_BN_NHW;

    local _FLOAT lscale, ldscale, ldbias, lmean, livar;

    if(get_local_id(1) == 0)
    {

#if(MIO_BN_USESAVED == 0)
        int ygrp_id                 = get_group_id(1);
        int ygrp_sz                 = get_local_size(1);
        unsigned int meanstashindex = cidx + ygrp_sz * ygrp_id + 1;
        unsigned int varstashindex  = cidx + ygrp_sz * ygrp_id + 3;
        lmean                       = *(dx_out + meanstashindex); // load stashed mean
        livar                       = *(dx_out + varstashindex);
#else  // SAVED
        lmean = *(savedMean + xgid);
        livar = *(savedInvVariance + xgid);
#endif // SAVED
        lscale                      = *(bnScale + xgid);
        ldscale                     = *(delta_scale + xgid);
        ldbias                      = *(delta_bias + xgid);
    }
    barrier(CLK_LOCAL_MEM_FENCE);
    //________________________________________________
    // Group level reduction
    // Need to reduce over all elements in NxHxW
    // move across the sections of an image in the mini_batch stack
    if(ygid < MIO_BN_HW)
    {

        mean   = lmean;
        invVar = livar;
        scale  = lscale;
        dscale = ldscale;
        dbias  = ldbias;

#pragma unroll
        for(unsigned int n = 0; n < MIO_BN_N; n++)
        { // apply normalization
            index         = n * MIO_BN_CHW + cidx + ygid;
            elemStd       = *(x_in + index) - mean; // (x_i - mean)
            xhat          = elemStd * invVar;       // recalculating this again...
            tmp1          = mad(NHW, *(dy_in + index), -dbias);
            tmp2          = -xhat * dscale;
            tmp3          = scale * invVar * INHW;
            dx_out[index] = tmp3 * (tmp2 + tmp1);
        }
    }
}

//============================================================

#endif // END VARIANTS

// Restore warnings
#ifdef __clang__
#pragma clang diagnostic pop
#pragma clang diagnostic pop
#endif
