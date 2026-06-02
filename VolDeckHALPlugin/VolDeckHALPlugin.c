#include <CoreAudio/AudioHardware.h>
#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <stddef.h>
#include <string.h>

enum {
    kVolDeckHALDeviceObjectID = 2,
    kVolDeckHALOutputStreamObjectID = 3,
};

enum {
    kVolDeckHALStereoChannels = 2,
    kVolDeckHALBitsPerChannel = 32,
    kVolDeckHALDefaultSampleRate = 48000,
    kVolDeckHALDefaultBufferFrames = 512,
    kVolDeckHALMinimumBufferFrames = 32,
    kVolDeckHALMaximumBufferFrames = 4096,
    kVolDeckHALZeroTimeStampPeriod = 16384,
};

static AudioServerPlugInHostRef gVolDeckHALHost = NULL;
static atomic_uint gVolDeckHALRefCount = 0;
static atomic_uint gVolDeckHALRunningClientCount = 0;
static _Atomic(UInt64) gVolDeckHALStartHostTime = 0;
static _Atomic(UInt64) gVolDeckHALClockSeed = 1;
static _Atomic(UInt32) gVolDeckHALBufferFrameSize = kVolDeckHALDefaultBufferFrames;
static _Atomic(UInt64) gVolDeckHALNominalSampleRate = kVolDeckHALDefaultSampleRate;

static HRESULT STDMETHODCALLTYPE VolDeckHALQueryInterface(void *inDriver, REFIID inUUID, LPVOID *outInterface);
static ULONG STDMETHODCALLTYPE VolDeckHALAddRef(void *inDriver);
static ULONG STDMETHODCALLTYPE VolDeckHALRelease(void *inDriver);
static OSStatus VolDeckHALInitialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost);
static OSStatus VolDeckHALCreateDevice(AudioServerPlugInDriverRef inDriver, CFDictionaryRef inDescription, const AudioServerPlugInClientInfo *inClientInfo, AudioObjectID *outDeviceObjectID);
static OSStatus VolDeckHALDestroyDevice(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID);
static OSStatus VolDeckHALAddDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo *inClientInfo);
static OSStatus VolDeckHALRemoveDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo *inClientInfo);
static OSStatus VolDeckHALPerformDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void *inChangeInfo);
static OSStatus VolDeckHALAbortDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void *inChangeInfo);
static Boolean VolDeckHALHasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress *inAddress);
static OSStatus VolDeckHALIsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress *inAddress, Boolean *outIsSettable);
static OSStatus VolDeckHALGetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress *inAddress, UInt32 inQualifierDataSize, const void *inQualifierData, UInt32 *outDataSize);
static OSStatus VolDeckHALGetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress *inAddress, UInt32 inQualifierDataSize, const void *inQualifierData, UInt32 inDataSize, UInt32 *outDataSize, void *outData);
static OSStatus VolDeckHALSetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress *inAddress, UInt32 inQualifierDataSize, const void *inQualifierData, UInt32 inDataSize, const void *inData);
static OSStatus VolDeckHALStartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID);
static OSStatus VolDeckHALStopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID);
static OSStatus VolDeckHALGetZeroTimeStamp(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, Float64 *outSampleTime, UInt64 *outHostTime, UInt64 *outSeed);
static OSStatus VolDeckHALWillDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, Boolean *outWillDo, Boolean *outWillDoInPlace);
static OSStatus VolDeckHALBeginIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo *inIOCycleInfo);
static OSStatus VolDeckHALDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, AudioObjectID inStreamObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo *inIOCycleInfo, void *ioMainBuffer, void *ioSecondaryBuffer);
static OSStatus VolDeckHALEndIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo *inIOCycleInfo);

static AudioServerPlugInDriverInterface gVolDeckHALDriverInterface = {
    NULL,
    VolDeckHALQueryInterface,
    VolDeckHALAddRef,
    VolDeckHALRelease,
    VolDeckHALInitialize,
    VolDeckHALCreateDevice,
    VolDeckHALDestroyDevice,
    VolDeckHALAddDeviceClient,
    VolDeckHALRemoveDeviceClient,
    VolDeckHALPerformDeviceConfigurationChange,
    VolDeckHALAbortDeviceConfigurationChange,
    VolDeckHALHasProperty,
    VolDeckHALIsPropertySettable,
    VolDeckHALGetPropertyDataSize,
    VolDeckHALGetPropertyData,
    VolDeckHALSetPropertyData,
    VolDeckHALStartIO,
    VolDeckHALStopIO,
    VolDeckHALGetZeroTimeStamp,
    VolDeckHALWillDoIOOperation,
    VolDeckHALBeginIOOperation,
    VolDeckHALDoIOOperation,
    VolDeckHALEndIOOperation,
};

static AudioServerPlugInDriverInterface *gVolDeckHALDriverInterfacePointer = &gVolDeckHALDriverInterface;

static CFUUIDRef VolDeckHALFactoryUUID(void)
{
    return CFUUIDGetConstantUUIDWithBytes(
        NULL,
        0x66, 0xD1, 0x24, 0x94, 0x2B, 0x15, 0x4B, 0x0F,
        0xA3, 0x65, 0x87, 0x92, 0x18, 0x21, 0x74, 0xC4);
}

static UInt64 VolDeckHALCurrentSampleRate(void)
{
    return atomic_load(&gVolDeckHALNominalSampleRate);
}

static AudioStreamBasicDescription VolDeckHALStreamDescription(Float64 sampleRate)
{
    AudioStreamBasicDescription description;
    memset(&description, 0, sizeof(description));
    description.mSampleRate = sampleRate;
    description.mFormatID = kAudioFormatLinearPCM;
    description.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian;
    description.mBytesPerPacket = sizeof(Float32) * kVolDeckHALStereoChannels;
    description.mFramesPerPacket = 1;
    description.mBytesPerFrame = sizeof(Float32) * kVolDeckHALStereoChannels;
    description.mChannelsPerFrame = kVolDeckHALStereoChannels;
    description.mBitsPerChannel = kVolDeckHALBitsPerChannel;
    return description;
}

static Boolean VolDeckHALIsSupportedSampleRate(Float64 sampleRate)
{
    return sampleRate == 44100.0 || sampleRate == 48000.0;
}

static Boolean VolDeckHALIsSupportedStreamDescription(const AudioStreamBasicDescription *description)
{
    if (description == NULL || !VolDeckHALIsSupportedSampleRate(description->mSampleRate)) {
        return false;
    }

    return description->mFormatID == kAudioFormatLinearPCM &&
        (description->mFormatFlags & kAudioFormatFlagIsFloat) == kAudioFormatFlagIsFloat &&
        description->mBytesPerPacket == sizeof(Float32) * kVolDeckHALStereoChannels &&
        description->mFramesPerPacket == 1 &&
        description->mBytesPerFrame == sizeof(Float32) * kVolDeckHALStereoChannels &&
        description->mChannelsPerFrame == kVolDeckHALStereoChannels &&
        description->mBitsPerChannel == kVolDeckHALBitsPerChannel;
}

static UInt32 VolDeckHALBufferListSize(UInt32 bufferCount)
{
    return (UInt32)(offsetof(AudioBufferList, mBuffers) + (sizeof(AudioBuffer) * bufferCount));
}

static OSStatus VolDeckHALCopyData(const void *source, UInt32 sourceSize, UInt32 inDataSize, UInt32 *outDataSize, void *outData)
{
    if (outDataSize == NULL || outData == NULL) {
        return kAudioHardwareIllegalOperationError;
    }

    *outDataSize = sourceSize;
    if (inDataSize < sourceSize) {
        return kAudioHardwareBadPropertySizeError;
    }

    if (sourceSize > 0 && source != NULL) {
        memcpy(outData, source, sourceSize);
    }

    return kAudioHardwareNoError;
}

static OSStatus VolDeckHALCopyCFString(CFStringRef string, UInt32 inDataSize, UInt32 *outDataSize, void *outData)
{
    CFStringRef retainedString = string;
    CFRetain(retainedString);
    return VolDeckHALCopyData(&retainedString, sizeof(retainedString), inDataSize, outDataSize, outData);
}

static OSStatus VolDeckHALCopyObjectList(const AudioObjectID *objects, UInt32 objectCount, UInt32 inDataSize, UInt32 *outDataSize, void *outData)
{
    return VolDeckHALCopyData(objects, sizeof(AudioObjectID) * objectCount, inDataSize, outDataSize, outData);
}

static OSStatus VolDeckHALCopyStreamConfiguration(Boolean outputScope, UInt32 inDataSize, UInt32 *outDataSize, void *outData)
{
    UInt32 bufferCount = outputScope ? 1 : 0;
    UInt32 requiredSize = VolDeckHALBufferListSize(bufferCount);
    if (outDataSize == NULL || outData == NULL) {
        return kAudioHardwareIllegalOperationError;
    }

    *outDataSize = requiredSize;
    if (inDataSize < requiredSize) {
        return kAudioHardwareBadPropertySizeError;
    }

    AudioBufferList *bufferList = (AudioBufferList *)outData;
    bufferList->mNumberBuffers = bufferCount;
    if (outputScope) {
        bufferList->mBuffers[0].mNumberChannels = kVolDeckHALStereoChannels;
        bufferList->mBuffers[0].mDataByteSize = 0;
        bufferList->mBuffers[0].mData = NULL;
    }

    return kAudioHardwareNoError;
}

static UInt32 VolDeckHALPropertyDataSize(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress)
{
    Boolean outputScope = inAddress->mScope != kAudioObjectPropertyScopeInput;

    switch (inObjectID) {
    case kAudioObjectPlugInObject:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioPlugInPropertyTranslateUIDToDevice:
            return sizeof(UInt32);
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioPlugInPropertyBundleID:
            return sizeof(CFStringRef);
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
            return sizeof(AudioObjectID);
        case kAudioPlugInPropertyBoxList:
        case kAudioPlugInPropertyClockDeviceList:
            return 0;
        default:
            return UINT32_MAX;
        }

    case kVolDeckHALDeviceObjectID:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyClockIsStable:
        case kAudioDevicePropertyClockAlgorithm:
        case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyBufferFrameSize:
        case kAudioDevicePropertyUsesVariableBufferFrameSizes:
            return sizeof(UInt32);
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyModelName:
        case kAudioObjectPropertyManufacturer:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
            return sizeof(CFStringRef);
        case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyStreams:
            return outputScope ? sizeof(AudioObjectID) : 0;
        case kAudioObjectPropertyControlList:
            return 0;
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyActualSampleRate:
            return sizeof(Float64);
        case kAudioDevicePropertyAvailableNominalSampleRates:
        case kAudioDevicePropertyBufferFrameSizeRange:
            return sizeof(AudioValueRange) * 2;
        case kAudioDevicePropertyPreferredChannelsForStereo:
            return outputScope ? sizeof(UInt32) * 2 : 0;
        case kAudioDevicePropertyStreamConfiguration:
            return VolDeckHALBufferListSize(outputScope ? 1 : 0);
        default:
            return UINT32_MAX;
        }

    case kVolDeckHALOutputStreamObjectID:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency:
            return sizeof(UInt32);
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
            return sizeof(CFStringRef);
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            return sizeof(AudioStreamBasicDescription);
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            return sizeof(AudioStreamRangedDescription) * 2;
        default:
            return UINT32_MAX;
        }

    default:
        return UINT32_MAX;
    }
}

static void VolDeckHALNotifyDeviceProperty(AudioObjectPropertySelector selector)
{
    if (gVolDeckHALHost == NULL || gVolDeckHALHost->PropertiesChanged == NULL) {
        return;
    }

    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    };
    gVolDeckHALHost->PropertiesChanged(gVolDeckHALHost, kVolDeckHALDeviceObjectID, 1, &address);
}

static void VolDeckHALNotifyStreamProperty(AudioObjectPropertySelector selector)
{
    if (gVolDeckHALHost == NULL || gVolDeckHALHost->PropertiesChanged == NULL) {
        return;
    }

    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    };
    gVolDeckHALHost->PropertiesChanged(gVolDeckHALHost, kVolDeckHALOutputStreamObjectID, 1, &address);
}

static void VolDeckHALNotifySampleRateProperties(void)
{
    VolDeckHALNotifyStreamProperty(kAudioStreamPropertyVirtualFormat);
    VolDeckHALNotifyStreamProperty(kAudioStreamPropertyPhysicalFormat);
    VolDeckHALNotifyDeviceProperty(kAudioDevicePropertyNominalSampleRate);
}

void *VolDeckHALPluginFactory(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID)
{
    (void)allocator;

    if (!CFEqual(requestedTypeUUID, kAudioServerPlugInTypeUUID)) {
        return NULL;
    }

    CFPlugInAddInstanceForFactory(VolDeckHALFactoryUUID());
    VolDeckHALAddRef(&gVolDeckHALDriverInterfacePointer);
    return &gVolDeckHALDriverInterfacePointer;
}

static HRESULT STDMETHODCALLTYPE VolDeckHALQueryInterface(void *inDriver, REFIID inUUID, LPVOID *outInterface)
{
    (void)inDriver;

    if (outInterface == NULL) {
        return E_POINTER;
    }

    CFUUIDRef requestedUUID = CFUUIDCreateFromUUIDBytes(NULL, inUUID);
    Boolean matches = CFEqual(requestedUUID, IUnknownUUID) || CFEqual(requestedUUID, kAudioServerPlugInDriverInterfaceUUID);
    CFRelease(requestedUUID);

    if (!matches) {
        *outInterface = NULL;
        return E_NOINTERFACE;
    }

    VolDeckHALAddRef(&gVolDeckHALDriverInterfacePointer);
    *outInterface = &gVolDeckHALDriverInterfacePointer;
    return S_OK;
}

static ULONG STDMETHODCALLTYPE VolDeckHALAddRef(void *inDriver)
{
    (void)inDriver;
    return atomic_fetch_add(&gVolDeckHALRefCount, 1) + 1;
}

static ULONG STDMETHODCALLTYPE VolDeckHALRelease(void *inDriver)
{
    (void)inDriver;

    UInt32 previousCount = atomic_load(&gVolDeckHALRefCount);
    while (previousCount > 0) {
        if (atomic_compare_exchange_weak(&gVolDeckHALRefCount, &previousCount, previousCount - 1)) {
            if (previousCount == 1) {
                CFPlugInRemoveInstanceForFactory(VolDeckHALFactoryUUID());
            }
            return previousCount - 1;
        }
    }

    return 0;
}

static OSStatus VolDeckHALInitialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost)
{
    (void)inDriver;
    gVolDeckHALHost = inHost;
    atomic_store(&gVolDeckHALRunningClientCount, 0);
    atomic_store(&gVolDeckHALStartHostTime, mach_absolute_time());
    atomic_store(&gVolDeckHALClockSeed, 1);
    atomic_store(&gVolDeckHALBufferFrameSize, kVolDeckHALDefaultBufferFrames);
    atomic_store(&gVolDeckHALNominalSampleRate, kVolDeckHALDefaultSampleRate);
    return kAudioHardwareNoError;
}

static OSStatus VolDeckHALCreateDevice(AudioServerPlugInDriverRef inDriver, CFDictionaryRef inDescription, const AudioServerPlugInClientInfo *inClientInfo, AudioObjectID *outDeviceObjectID)
{
    (void)inDriver;
    (void)inDescription;
    (void)inClientInfo;
    (void)outDeviceObjectID;
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus VolDeckHALDestroyDevice(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID)
{
    (void)inDriver;
    (void)inDeviceObjectID;
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus VolDeckHALAddDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo *inClientInfo)
{
    (void)inDriver;
    (void)inClientInfo;
    return inDeviceObjectID == kVolDeckHALDeviceObjectID ? kAudioHardwareNoError : kAudioHardwareBadDeviceError;
}

static OSStatus VolDeckHALRemoveDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo *inClientInfo)
{
    (void)inDriver;
    (void)inClientInfo;
    return inDeviceObjectID == kVolDeckHALDeviceObjectID ? kAudioHardwareNoError : kAudioHardwareBadDeviceError;
}

static OSStatus VolDeckHALPerformDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void *inChangeInfo)
{
    (void)inDriver;
    (void)inChangeAction;
    (void)inChangeInfo;
    return inDeviceObjectID == kVolDeckHALDeviceObjectID ? kAudioHardwareNoError : kAudioHardwareBadDeviceError;
}

static OSStatus VolDeckHALAbortDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void *inChangeInfo)
{
    (void)inDriver;
    (void)inChangeAction;
    (void)inChangeInfo;
    return inDeviceObjectID == kVolDeckHALDeviceObjectID ? kAudioHardwareNoError : kAudioHardwareBadDeviceError;
}

static Boolean VolDeckHALHasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress *inAddress)
{
    (void)inDriver;
    (void)inClientProcessID;
    return inAddress != NULL && VolDeckHALPropertyDataSize(inObjectID, inAddress) != UINT32_MAX;
}

static OSStatus VolDeckHALIsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress *inAddress, Boolean *outIsSettable)
{
    (void)inDriver;
    (void)inClientProcessID;

    if (inAddress == NULL || outIsSettable == NULL) {
        return kAudioHardwareIllegalOperationError;
    }

    *outIsSettable = false;
    if (inObjectID == kVolDeckHALDeviceObjectID &&
        (inAddress->mSelector == kAudioDevicePropertyNominalSampleRate || inAddress->mSelector == kAudioDevicePropertyBufferFrameSize)) {
        *outIsSettable = true;
    }

    if (inObjectID == kVolDeckHALOutputStreamObjectID &&
        (inAddress->mSelector == kAudioStreamPropertyVirtualFormat || inAddress->mSelector == kAudioStreamPropertyPhysicalFormat)) {
        *outIsSettable = true;
    }

    return VolDeckHALHasProperty(inDriver, inObjectID, inClientProcessID, inAddress) ? kAudioHardwareNoError : kAudioHardwareUnknownPropertyError;
}

static OSStatus VolDeckHALGetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress *inAddress, UInt32 inQualifierDataSize, const void *inQualifierData, UInt32 *outDataSize)
{
    (void)inDriver;
    (void)inClientProcessID;
    (void)inQualifierDataSize;
    (void)inQualifierData;

    if (inAddress == NULL || outDataSize == NULL) {
        return kAudioHardwareIllegalOperationError;
    }

    UInt32 size = VolDeckHALPropertyDataSize(inObjectID, inAddress);
    if (size == UINT32_MAX) {
        return kAudioHardwareUnknownPropertyError;
    }

    *outDataSize = size;
    return kAudioHardwareNoError;
}

static OSStatus VolDeckHALGetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress *inAddress, UInt32 inQualifierDataSize, const void *inQualifierData, UInt32 inDataSize, UInt32 *outDataSize, void *outData)
{
    (void)inDriver;
    (void)inClientProcessID;
    (void)inQualifierDataSize;

    if (inAddress == NULL) {
        return kAudioHardwareIllegalOperationError;
    }

    AudioClassID classID;
    AudioObjectID objectID;
    UInt32 value32;
    Float64 value64;
    AudioObjectID outputStream = kVolDeckHALOutputStreamObjectID;
    AudioObjectID device = kVolDeckHALDeviceObjectID;
    AudioValueRange ranges[2];
    UInt32 stereoChannels[2] = { 1, 2 };
    AudioStreamBasicDescription streamDescription;
    AudioStreamRangedDescription rangedDescriptions[2];
    Boolean outputScope = inAddress->mScope != kAudioObjectPropertyScopeInput;

    switch (inObjectID) {
    case kAudioObjectPlugInObject:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
            classID = kAudioObjectClassID;
            return VolDeckHALCopyData(&classID, sizeof(classID), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyClass:
            classID = kAudioPlugInClassID;
            return VolDeckHALCopyData(&classID, sizeof(classID), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyOwner:
            objectID = kAudioObjectUnknown;
            return VolDeckHALCopyData(&objectID, sizeof(objectID), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyName:
            return VolDeckHALCopyCFString(CFSTR("VolDeck HAL Plugin"), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyManufacturer:
            return VolDeckHALCopyCFString(CFSTR("VolDeck"), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
            return VolDeckHALCopyObjectList(&device, 1, inDataSize, outDataSize, outData);
        case kAudioPlugInPropertyTranslateUIDToDevice:
            objectID = kAudioObjectUnknown;
            if (inQualifierData != NULL && inQualifierDataSize == sizeof(CFStringRef)) {
                CFStringRef requestedUID = *(const CFStringRef *)inQualifierData;
                if (requestedUID != NULL && CFEqual(requestedUID, CFSTR("com.peerapatj.voldeck.output"))) {
                    objectID = kVolDeckHALDeviceObjectID;
                }
            }
            return VolDeckHALCopyData(&objectID, sizeof(objectID), inDataSize, outDataSize, outData);
        case kAudioPlugInPropertyBundleID:
            return VolDeckHALCopyCFString(CFSTR("com.peerapatj.voldeck.halplugin"), inDataSize, outDataSize, outData);
        case kAudioPlugInPropertyBoxList:
        case kAudioPlugInPropertyClockDeviceList:
            return VolDeckHALCopyData(NULL, 0, inDataSize, outDataSize, outData);
        default:
            return kAudioHardwareUnknownPropertyError;
        }

    case kVolDeckHALDeviceObjectID:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
            classID = kAudioObjectClassID;
            return VolDeckHALCopyData(&classID, sizeof(classID), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyClass:
            classID = kAudioDeviceClassID;
            return VolDeckHALCopyData(&classID, sizeof(classID), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyOwner:
            objectID = kAudioObjectPlugInObject;
            return VolDeckHALCopyData(&objectID, sizeof(objectID), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyName:
            return VolDeckHALCopyCFString(CFSTR("VolDeck"), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyModelName:
            return VolDeckHALCopyCFString(CFSTR("VolDeck Output-only Prototype"), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyManufacturer:
            return VolDeckHALCopyCFString(CFSTR("VolDeck"), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyStreams:
            return outputScope ? VolDeckHALCopyObjectList(&outputStream, 1, inDataSize, outDataSize, outData) : VolDeckHALCopyData(NULL, 0, inDataSize, outDataSize, outData);
        case kAudioObjectPropertyControlList:
            return VolDeckHALCopyData(NULL, 0, inDataSize, outDataSize, outData);
        case kAudioDevicePropertyDeviceUID:
            return VolDeckHALCopyCFString(CFSTR("com.peerapatj.voldeck.output"), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyModelUID:
            return VolDeckHALCopyCFString(CFSTR("com.peerapatj.voldeck.output-only-prototype"), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyTransportType:
            value32 = kAudioDeviceTransportTypeVirtual;
            return VolDeckHALCopyData(&value32, sizeof(value32), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyUsesVariableBufferFrameSizes:
            value32 = 0;
            return VolDeckHALCopyData(&value32, sizeof(value32), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyClockIsStable:
            value32 = 1;
            return VolDeckHALCopyData(&value32, sizeof(value32), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyDeviceIsRunning:
            value32 = atomic_load(&gVolDeckHALRunningClientCount) > 0 ? 1 : 0;
            return VolDeckHALCopyData(&value32, sizeof(value32), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
            value32 = outputScope ? 1 : 0;
            return VolDeckHALCopyData(&value32, sizeof(value32), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyActualSampleRate:
            value64 = (Float64)VolDeckHALCurrentSampleRate();
            return VolDeckHALCopyData(&value64, sizeof(value64), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyAvailableNominalSampleRates:
            ranges[0].mMinimum = 44100.0;
            ranges[0].mMaximum = 44100.0;
            ranges[1].mMinimum = 48000.0;
            ranges[1].mMaximum = 48000.0;
            return VolDeckHALCopyData(ranges, sizeof(ranges), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyPreferredChannelsForStereo:
            return outputScope ? VolDeckHALCopyData(stereoChannels, sizeof(stereoChannels), inDataSize, outDataSize, outData) : VolDeckHALCopyData(NULL, 0, inDataSize, outDataSize, outData);
        case kAudioDevicePropertyStreamConfiguration:
            return VolDeckHALCopyStreamConfiguration(outputScope, inDataSize, outDataSize, outData);
        case kAudioDevicePropertyClockAlgorithm:
            value32 = kAudioDeviceClockAlgorithmRaw;
            return VolDeckHALCopyData(&value32, sizeof(value32), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyZeroTimeStampPeriod:
            value32 = kVolDeckHALZeroTimeStampPeriod;
            return VolDeckHALCopyData(&value32, sizeof(value32), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyBufferFrameSize:
            value32 = atomic_load(&gVolDeckHALBufferFrameSize);
            return VolDeckHALCopyData(&value32, sizeof(value32), inDataSize, outDataSize, outData);
        case kAudioDevicePropertyBufferFrameSizeRange:
            ranges[0].mMinimum = kVolDeckHALMinimumBufferFrames;
            ranges[0].mMaximum = kVolDeckHALMaximumBufferFrames;
            ranges[1].mMinimum = kVolDeckHALDefaultBufferFrames;
            ranges[1].mMaximum = kVolDeckHALDefaultBufferFrames;
            return VolDeckHALCopyData(ranges, sizeof(ranges), inDataSize, outDataSize, outData);
        default:
            return kAudioHardwareUnknownPropertyError;
        }

    case kVolDeckHALOutputStreamObjectID:
        switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
            classID = kAudioObjectClassID;
            return VolDeckHALCopyData(&classID, sizeof(classID), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyClass:
            classID = kAudioStreamClassID;
            return VolDeckHALCopyData(&classID, sizeof(classID), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyOwner:
            objectID = kVolDeckHALDeviceObjectID;
            return VolDeckHALCopyData(&objectID, sizeof(objectID), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyName:
            return VolDeckHALCopyCFString(CFSTR("VolDeck Output Stream"), inDataSize, outDataSize, outData);
        case kAudioObjectPropertyManufacturer:
            return VolDeckHALCopyCFString(CFSTR("VolDeck"), inDataSize, outDataSize, outData);
        case kAudioStreamPropertyIsActive:
            value32 = 1;
            return VolDeckHALCopyData(&value32, sizeof(value32), inDataSize, outDataSize, outData);
        case kAudioStreamPropertyDirection:
            value32 = 0;
            return VolDeckHALCopyData(&value32, sizeof(value32), inDataSize, outDataSize, outData);
        case kAudioStreamPropertyTerminalType:
            value32 = kAudioStreamTerminalTypeSpeaker;
            return VolDeckHALCopyData(&value32, sizeof(value32), inDataSize, outDataSize, outData);
        case kAudioStreamPropertyStartingChannel:
            value32 = 1;
            return VolDeckHALCopyData(&value32, sizeof(value32), inDataSize, outDataSize, outData);
        case kAudioStreamPropertyLatency:
            value32 = 0;
            return VolDeckHALCopyData(&value32, sizeof(value32), inDataSize, outDataSize, outData);
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            streamDescription = VolDeckHALStreamDescription((Float64)VolDeckHALCurrentSampleRate());
            return VolDeckHALCopyData(&streamDescription, sizeof(streamDescription), inDataSize, outDataSize, outData);
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            rangedDescriptions[0].mFormat = VolDeckHALStreamDescription(44100.0);
            rangedDescriptions[0].mSampleRateRange.mMinimum = 44100.0;
            rangedDescriptions[0].mSampleRateRange.mMaximum = 44100.0;
            rangedDescriptions[1].mFormat = VolDeckHALStreamDescription(48000.0);
            rangedDescriptions[1].mSampleRateRange.mMinimum = 48000.0;
            rangedDescriptions[1].mSampleRateRange.mMaximum = 48000.0;
            return VolDeckHALCopyData(rangedDescriptions, sizeof(rangedDescriptions), inDataSize, outDataSize, outData);
        default:
            return kAudioHardwareUnknownPropertyError;
        }

    default:
        return kAudioHardwareBadObjectError;
    }
}

static OSStatus VolDeckHALSetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress *inAddress, UInt32 inQualifierDataSize, const void *inQualifierData, UInt32 inDataSize, const void *inData)
{
    (void)inDriver;
    (void)inClientProcessID;
    (void)inQualifierDataSize;
    (void)inQualifierData;

    if (inAddress == NULL || inData == NULL) {
        return kAudioHardwareIllegalOperationError;
    }

    if (inObjectID == kVolDeckHALDeviceObjectID && inAddress->mSelector == kAudioDevicePropertyNominalSampleRate) {
        if (inDataSize != sizeof(Float64)) {
            return kAudioHardwareBadPropertySizeError;
        }

        Float64 requestedSampleRate = *(const Float64 *)inData;
        if (!VolDeckHALIsSupportedSampleRate(requestedSampleRate)) {
            return kAudioDeviceUnsupportedFormatError;
        }

        atomic_store(&gVolDeckHALNominalSampleRate, (UInt64)requestedSampleRate);
        atomic_fetch_add(&gVolDeckHALClockSeed, 1);
        VolDeckHALNotifySampleRateProperties();
        return kAudioHardwareNoError;
    }

    if (inObjectID == kVolDeckHALDeviceObjectID && inAddress->mSelector == kAudioDevicePropertyBufferFrameSize) {
        if (inDataSize != sizeof(UInt32)) {
            return kAudioHardwareBadPropertySizeError;
        }

        UInt32 requestedBufferSize = *(const UInt32 *)inData;
        if (requestedBufferSize < kVolDeckHALMinimumBufferFrames || requestedBufferSize > kVolDeckHALMaximumBufferFrames) {
            return kAudioHardwareIllegalOperationError;
        }

        atomic_store(&gVolDeckHALBufferFrameSize, requestedBufferSize);
        VolDeckHALNotifyDeviceProperty(kAudioDevicePropertyBufferFrameSize);
        return kAudioHardwareNoError;
    }

    if (inObjectID == kVolDeckHALOutputStreamObjectID &&
        (inAddress->mSelector == kAudioStreamPropertyVirtualFormat || inAddress->mSelector == kAudioStreamPropertyPhysicalFormat)) {
        if (inDataSize != sizeof(AudioStreamBasicDescription)) {
            return kAudioHardwareBadPropertySizeError;
        }

        const AudioStreamBasicDescription *requestedDescription = (const AudioStreamBasicDescription *)inData;
        if (!VolDeckHALIsSupportedStreamDescription(requestedDescription)) {
            return kAudioDeviceUnsupportedFormatError;
        }

        atomic_store(&gVolDeckHALNominalSampleRate, (UInt64)requestedDescription->mSampleRate);
        atomic_fetch_add(&gVolDeckHALClockSeed, 1);
        VolDeckHALNotifySampleRateProperties();
        return kAudioHardwareNoError;
    }

    return kAudioHardwareIllegalOperationError;
}

static OSStatus VolDeckHALStartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID)
{
    (void)inDriver;
    (void)inClientID;

    if (inDeviceObjectID != kVolDeckHALDeviceObjectID) {
        return kAudioHardwareBadDeviceError;
    }

    if (atomic_fetch_add(&gVolDeckHALRunningClientCount, 1) == 0) {
        atomic_store(&gVolDeckHALStartHostTime, mach_absolute_time());
        atomic_fetch_add(&gVolDeckHALClockSeed, 1);
        VolDeckHALNotifyDeviceProperty(kAudioDevicePropertyDeviceIsRunning);
    }

    return kAudioHardwareNoError;
}

static OSStatus VolDeckHALStopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID)
{
    (void)inDriver;
    (void)inClientID;

    if (inDeviceObjectID != kVolDeckHALDeviceObjectID) {
        return kAudioHardwareBadDeviceError;
    }

    UInt32 previousCount = atomic_load(&gVolDeckHALRunningClientCount);
    while (previousCount > 0) {
        if (atomic_compare_exchange_weak(&gVolDeckHALRunningClientCount, &previousCount, previousCount - 1)) {
            if (previousCount == 1) {
                VolDeckHALNotifyDeviceProperty(kAudioDevicePropertyDeviceIsRunning);
            }
            return kAudioHardwareNoError;
        }
    }

    return kAudioHardwareNoError;
}

static OSStatus VolDeckHALGetZeroTimeStamp(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, Float64 *outSampleTime, UInt64 *outHostTime, UInt64 *outSeed)
{
    (void)inDriver;
    (void)inClientID;

    if (inDeviceObjectID != kVolDeckHALDeviceObjectID) {
        return kAudioHardwareBadDeviceError;
    }

    if (outSampleTime == NULL || outHostTime == NULL || outSeed == NULL) {
        return kAudioHardwareIllegalOperationError;
    }

    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);

    UInt64 now = mach_absolute_time();
    UInt64 start = atomic_load(&gVolDeckHALStartHostTime);
    if (start == 0 || now < start) {
        start = now;
        atomic_store(&gVolDeckHALStartHostTime, start);
    }

    Float64 ticksPerSecond = 1000000000.0 * (Float64)timebase.denom / (Float64)timebase.numer;
    Float64 elapsedFrames = ((Float64)(now - start) / ticksPerSecond) * (Float64)VolDeckHALCurrentSampleRate();

    *outSampleTime = (Float64)((UInt64)elapsedFrames);
    *outHostTime = now;
    *outSeed = atomic_load(&gVolDeckHALClockSeed);
    return kAudioHardwareNoError;
}

static OSStatus VolDeckHALWillDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, Boolean *outWillDo, Boolean *outWillDoInPlace)
{
    (void)inDriver;
    (void)inClientID;

    if (inDeviceObjectID != kVolDeckHALDeviceObjectID) {
        return kAudioHardwareBadDeviceError;
    }

    if (outWillDo == NULL || outWillDoInPlace == NULL) {
        return kAudioHardwareIllegalOperationError;
    }

    *outWillDo = inOperationID == kAudioServerPlugInIOOperationWriteMix;
    *outWillDoInPlace = true;
    return kAudioHardwareNoError;
}

static OSStatus VolDeckHALBeginIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo *inIOCycleInfo)
{
    (void)inDriver;
    (void)inClientID;
    (void)inOperationID;
    (void)inIOBufferFrameSize;
    (void)inIOCycleInfo;
    return inDeviceObjectID == kVolDeckHALDeviceObjectID ? kAudioHardwareNoError : kAudioHardwareBadDeviceError;
}

static OSStatus VolDeckHALDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, AudioObjectID inStreamObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo *inIOCycleInfo, void *ioMainBuffer, void *ioSecondaryBuffer)
{
    (void)inDriver;
    (void)inClientID;
    (void)inIOBufferFrameSize;
    (void)inIOCycleInfo;
    (void)ioMainBuffer;
    (void)ioSecondaryBuffer;

    if (inDeviceObjectID != kVolDeckHALDeviceObjectID || inStreamObjectID != kVolDeckHALOutputStreamObjectID) {
        return kAudioHardwareBadDeviceError;
    }

    return inOperationID == kAudioServerPlugInIOOperationWriteMix ? kAudioHardwareNoError : kAudioHardwareUnsupportedOperationError;
}

static OSStatus VolDeckHALEndIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo *inIOCycleInfo)
{
    (void)inDriver;
    (void)inClientID;
    (void)inOperationID;
    (void)inIOBufferFrameSize;
    (void)inIOCycleInfo;
    return inDeviceObjectID == kVolDeckHALDeviceObjectID ? kAudioHardwareNoError : kAudioHardwareBadDeviceError;
}
