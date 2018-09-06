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
#include <array>
#include <initializer_list>
#include <memory>
#include <miopen/convolution.hpp>
#include <miopen/batch_norm.hpp>
#include <miopen/activ.hpp>
#include <miopen/fusion.hpp>
#include <miopen/fusion_plan.hpp>
#include <miopen/errors.hpp>
#include <miopen/logger.hpp>
#include <miopen/tensor.hpp>

// Return an error code that is "NotImplemented", if it exists then return success
// This function should:
//		set up the place descriptor with expected input and ouput edges.
// 		Set up the internal datastructures for the fused kernel.
extern "C" miopenStatus_t miopenCreateFusionPlan(miopenFusionPlanDescriptor_t* fusePlanDesc,
                                                 const miopenFusionDirection_t fuseDirection,
                                                 const miopenTensorDescriptor_t inputDesc)
{
    MIOPEN_LOG_FUNCTION(fusePlanDesc, fuseDirection, inputDesc);
    return miopen::try_([&] {
        miopen::deref(fusePlanDesc) =
            new miopen::FusionPlanDescriptor(fuseDirection, miopen::deref(inputDesc));
    });
}

extern "C" miopenStatus_t
miopenDestroyFusionPlanDescriptor(miopenFusionPlanDescriptor_t fusePlanDesc)
{

    MIOPEN_LOG_FUNCTION(fusePlanDesc)
    return miopen::try_([&] { miopen_destroy_object(fusePlanDesc); });
}

extern "C" miopenStatus_t miopenFusionPlanGetOp(miopenFusionPlanDescriptor_t fusePlanDesc,
                                                const int op_idx,
                                                miopenFusionOpDescriptor_t* op)
{
    MIOPEN_LOG_FUNCTION(fusePlanDesc, op_idx);
    miopenStatus_t res = miopenStatusBadParm;
    miopen::try_([&] {
        std::shared_ptr<miopen::FusionOpDescriptor> desc;
        res               = miopen::deref(fusePlanDesc).GetOp(op_idx, desc);
        miopen::deref(op) = desc.get();
    });
    return res;
}

// Return an error code that is "NotImplemented", if it exists then return success
extern "C" miopenStatus_t miopenCompileFusionPlan(miopenHandle_t handle,
                                                  miopenFusionPlanDescriptor_t fusePlanDesc)
{
    MIOPEN_LOG_FUNCTION(/*handle,*/ fusePlanDesc);
    return miopen::try_([&] { miopen::deref(fusePlanDesc).Compile(miopen::deref(handle)); });
}

// Activation create ops
extern "C" miopenStatus_t miopenCreateOpActivationForward(miopenFusionPlanDescriptor_t fusePlanDesc,
                                                          miopenFusionOpDescriptor_t* activOp,
                                                          miopenActivationMode_t mode)
{
    MIOPEN_LOG_FUNCTION(fusePlanDesc, activOp, mode);
    miopenStatus_t res = miopenStatusSuccess;
    miopen::try_([&] {
        auto fod               = std::make_shared<miopen::ActivFusionOpDescriptor>(mode);
        miopen::deref(activOp) = fod.get();
        res                    = miopen::deref(fusePlanDesc).AddOp(fod);
    });
    return res;
}

// Batch normalization create op
extern "C" miopenStatus_t
miopenCreateOpBatchNormInference(miopenFusionPlanDescriptor_t fusePlanDesc,
                                 miopenFusionOpDescriptor_t* bnOp,
                                 const miopenBatchNormMode_t bn_mode,
                                 const miopenTensorDescriptor_t bnScaleBiasMeanVarDesc)
{
    MIOPEN_LOG_FUNCTION(fusePlanDesc, bnOp, bn_mode, bnScaleBiasMeanVarDesc);
    miopenStatus_t res = miopenStatusSuccess;
    miopen::try_([&] {
        auto bod = std::make_shared<miopen::BatchNormInferenceFusionOpDescriptor>(
            bn_mode, miopen::deref(bnScaleBiasMeanVarDesc));
        miopen::deref(bnOp) = bod.get();
        res                 = miopen::deref(fusePlanDesc).AddOp(bod);
    });
    return res;
}

extern "C" miopenStatus_t miopenCreateOperatorArgs(miopenOperatorArgs_t* args)
{
    MIOPEN_LOG_FUNCTION(args);
    return miopen::try_([&] { miopen::deref(args) = new miopen::OperatorArgs(); });
}

extern "C" miopenStatus_t miopenDestroyOperatorArgs(miopenOperatorArgs_t args)
{
    MIOPEN_LOG_FUNCTION(args);
    return miopen::try_([&] { miopen_destroy_object(args); });
}

extern "C" miopenStatus_t miopenSetOpArgsActivForward(miopenOperatorArgs_t args,
                                                      const miopenFusionOpDescriptor_t activOp,
                                                      const void* alpha,
                                                      const void* beta,
                                                      double activAlpha,
                                                      double activBeta,
                                                      double activGamma)
{

    MIOPEN_LOG_FUNCTION(args, activOp, alpha, beta, activAlpha, activBeta, activGamma);
    return miopen::try_([&] {
        auto&& op = dynamic_cast<miopen::ActivFusionOpDescriptor&>(miopen::deref(activOp));
        op.SetArgs(miopen::deref(args), alpha, beta, activAlpha, activBeta, activGamma);
    });
}

// Fusion op args for Batch Normalization
extern "C" miopenStatus_t miopenSetOpArgsBatchNormInference(miopenOperatorArgs_t args,
                                                            const miopenFusionOpDescriptor_t bnOp,
                                                            const void* alpha,
                                                            const void* beta,
                                                            const void* bnScale,
                                                            const void* bnBias,
                                                            const void* estimatedMean,
                                                            const void* estimatedVariance,
                                                            double epsilon)
{
    MIOPEN_LOG_FUNCTION(
        args, bnOp, alpha, beta, bnScale, bnBias, estimatedMean, estimatedVariance, epsilon);
    return miopen::try_([&] {
        auto&& op =
            dynamic_cast<miopen::BatchNormInferenceFusionOpDescriptor&>(miopen::deref(bnOp));
        op.SetArgs(miopen::deref(args),
                   alpha,
                   beta,
                   DataCast(bnScale),
                   DataCast(bnBias),
                   DataCast(estimatedMean),
                   DataCast(estimatedVariance),
                   epsilon);
    });
}
// Return an error code that is "NotImplemented", if it exists then return success
extern "C" miopenStatus_t miopenExecuteFusionPlan(const miopenHandle_t handle,
                                                  const miopenFusionPlanDescriptor_t fusePlanDesc,
                                                  const miopenTensorDescriptor_t inputDesc,
                                                  const void* input,
                                                  const miopenTensorDescriptor_t outputDesc,
                                                  void* output,
                                                  miopenOperatorArgs_t args)
{
    MIOPEN_LOG_FUNCTION(fusePlanDesc, inputDesc, input, outputDesc, output, args);
    return miopen::try_([&] {

        miopen::deref(fusePlanDesc)
            .Execute(miopen::deref(handle),
                     miopen::deref(inputDesc),
                     DataCast(input),
                     miopen::deref(outputDesc),
                     DataCast(output),
                     miopen::deref(args));
    });
}
