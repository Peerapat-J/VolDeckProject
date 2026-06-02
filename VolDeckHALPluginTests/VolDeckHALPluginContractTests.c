#include <CoreAudio/AudioHardware.h>
#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "../VolDeckHALPlugin/VolDeckHALPlugin.c"

static int gFailureCount = 0;

static void RecordFailure(const char *file, int line, const char *message)
{
    fprintf(stderr, "%s:%d: %s\n", file, line, message);
    gFailureCount += 1;
}

#define EXPECT_TRUE(condition) \
    do { \
        if (!(condition)) { \
            RecordFailure(__FILE__, __LINE__, "expected true: " #condition); \
        } \
    } while (0)

#define EXPECT_STATUS(expression, expected) \
    do { \
        OSStatus actualStatus = (expression); \
        if (actualStatus != (expected)) { \
            char message[160]; \
            snprintf(message, sizeof(message), "expected status %d but got %d: %s", (int)(expected), (int)actualStatus, #expression); \
            RecordFailure(__FILE__, __LINE__, message); \
        } \
    } while (0)

#define EXPECT_UINT32(actual, expected) \
    do { \
        UInt32 actualValue = (actual); \
        UInt32 expectedValue = (expected); \
        if (actualValue != expectedValue) { \
            char message[160]; \
            snprintf(message, sizeof(message), "expected %u but got %u: %s", expectedValue, actualValue, #actual); \
            RecordFailure(__FILE__, __LINE__, message); \
        } \
    } while (0)

#define EXPECT_FLOAT64(actual, expected) \
    do { \
        Float64 actualValue = (actual); \
        Float64 expectedValue = (expected); \
        if (actualValue != expectedValue) { \
            char message[160]; \
            snprintf(message, sizeof(message), "expected %.1f but got %.1f: %s", expectedValue, actualValue, #actual); \
            RecordFailure(__FILE__, __LINE__, message); \
        } \
    } while (0)

static AudioObjectPropertyAddress Address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress address = {
        selector,
        scope,
        kAudioObjectPropertyElementMain,
    };
    return address;
}

static OSStatus GetSize(AudioObjectID objectID, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope, UInt32 *outSize)
{
    AudioObjectPropertyAddress address = Address(selector, scope);
    return VolDeckHALGetPropertyDataSize(&gVolDeckHALDriverInterfacePointer, objectID, 0, &address, 0, NULL, outSize);
}

static OSStatus GetData(
    AudioObjectID objectID,
    AudioObjectPropertySelector selector,
    AudioObjectPropertyScope scope,
    UInt32 qualifierDataSize,
    const void *qualifierData,
    UInt32 dataSize,
    UInt32 *outDataSize,
    void *outData)
{
    AudioObjectPropertyAddress address = Address(selector, scope);
    return VolDeckHALGetPropertyData(
        &gVolDeckHALDriverInterfacePointer,
        objectID,
        0,
        &address,
        qualifierDataSize,
        qualifierData,
        dataSize,
        outDataSize,
        outData);
}

static OSStatus SetData(AudioObjectID objectID, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope, UInt32 dataSize, const void *data)
{
    AudioObjectPropertyAddress address = Address(selector, scope);
    return VolDeckHALSetPropertyData(&gVolDeckHALDriverInterfacePointer, objectID, 0, &address, 0, NULL, dataSize, data);
}

static UInt32 GetUInt32(AudioObjectID objectID, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope)
{
    UInt32 value = 0;
    UInt32 dataSize = 0;
    EXPECT_STATUS(GetData(objectID, selector, scope, 0, NULL, sizeof(value), &dataSize, &value), kAudioHardwareNoError);
    EXPECT_UINT32(dataSize, sizeof(value));
    return value;
}

static Float64 GetFloat64(AudioObjectID objectID, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope)
{
    Float64 value = 0.0;
    UInt32 dataSize = 0;
    EXPECT_STATUS(GetData(objectID, selector, scope, 0, NULL, sizeof(value), &dataSize, &value), kAudioHardwareNoError);
    EXPECT_UINT32(dataSize, sizeof(value));
    return value;
}

static void TestPluginPublishesOneDevice(void)
{
    AudioObjectID devices[2] = { 0, 0 };
    UInt32 dataSize = 0;

    EXPECT_STATUS(GetSize(kAudioObjectPlugInObject, kAudioPlugInPropertyDeviceList, kAudioObjectPropertyScopeGlobal, &dataSize), kAudioHardwareNoError);
    EXPECT_UINT32(dataSize, sizeof(AudioObjectID));
    EXPECT_STATUS(GetData(kAudioObjectPlugInObject, kAudioPlugInPropertyDeviceList, kAudioObjectPropertyScopeGlobal, 0, NULL, sizeof(devices), &dataSize, devices), kAudioHardwareNoError);
    EXPECT_UINT32(devices[0], kVolDeckHALDeviceObjectID);

    CFStringRef uid = CFSTR("com.peerapatj.voldeck.output");
    AudioObjectID translatedDevice = kAudioObjectUnknown;
    EXPECT_STATUS(
        GetData(kAudioObjectPlugInObject, kAudioPlugInPropertyTranslateUIDToDevice, kAudioObjectPropertyScopeGlobal, sizeof(uid), &uid, sizeof(translatedDevice), &dataSize, &translatedDevice),
        kAudioHardwareNoError);
    EXPECT_UINT32(translatedDevice, kVolDeckHALDeviceObjectID);
}

static void TestDeviceIsOutputOnly(void)
{
    UInt32 dataSize = 0;
    UInt8 scratch[128];
    AudioObjectID outputStreams[2] = { 0, 0 };

    EXPECT_STATUS(GetSize(kVolDeckHALDeviceObjectID, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput, &dataSize), kAudioHardwareNoError);
    EXPECT_UINT32(dataSize, 0);
    EXPECT_STATUS(GetData(kVolDeckHALDeviceObjectID, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput, 0, NULL, sizeof(scratch), &dataSize, scratch), kAudioHardwareNoError);
    EXPECT_UINT32(dataSize, 0);

    EXPECT_STATUS(GetSize(kVolDeckHALDeviceObjectID, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput, &dataSize), kAudioHardwareNoError);
    EXPECT_UINT32(dataSize, sizeof(AudioObjectID));
    EXPECT_STATUS(GetData(kVolDeckHALDeviceObjectID, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput, 0, NULL, sizeof(outputStreams), &dataSize, outputStreams), kAudioHardwareNoError);
    EXPECT_UINT32(outputStreams[0], kVolDeckHALOutputStreamObjectID);

    EXPECT_STATUS(GetSize(kVolDeckHALDeviceObjectID, kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput, &dataSize), kAudioHardwareNoError);
    EXPECT_UINT32(dataSize, (UInt32)offsetof(AudioBufferList, mBuffers));
    EXPECT_STATUS(GetData(kVolDeckHALDeviceObjectID, kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput, 0, NULL, sizeof(scratch), &dataSize, scratch), kAudioHardwareNoError);
    const AudioBufferList *inputBufferList = (const AudioBufferList *)scratch;
    EXPECT_UINT32(inputBufferList->mNumberBuffers, 0);

    EXPECT_STATUS(GetData(kVolDeckHALDeviceObjectID, kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput, 0, NULL, sizeof(scratch), &dataSize, scratch), kAudioHardwareNoError);
    const AudioBufferList *outputBufferList = (const AudioBufferList *)scratch;
    EXPECT_UINT32(outputBufferList->mNumberBuffers, 1);
    EXPECT_UINT32(outputBufferList->mBuffers[0].mNumberChannels, 2);
    EXPECT_UINT32(GetUInt32(kVolDeckHALOutputStreamObjectID, kAudioStreamPropertyDirection, kAudioObjectPropertyScopeGlobal), 0);
    EXPECT_UINT32(GetUInt32(kVolDeckHALOutputStreamObjectID, kAudioStreamPropertyTerminalType, kAudioObjectPropertyScopeGlobal), kAudioStreamTerminalTypeSpeaker);
}

static void TestDefaultDeviceFlagsStayOutputScoped(void)
{
    EXPECT_UINT32(GetUInt32(kVolDeckHALDeviceObjectID, kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioObjectPropertyScopeOutput), 1);
    EXPECT_UINT32(GetUInt32(kVolDeckHALDeviceObjectID, kAudioDevicePropertyDeviceCanBeDefaultSystemDevice, kAudioObjectPropertyScopeOutput), 1);
    EXPECT_UINT32(GetUInt32(kVolDeckHALDeviceObjectID, kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioObjectPropertyScopeInput), 0);
    EXPECT_UINT32(GetUInt32(kVolDeckHALDeviceObjectID, kAudioDevicePropertyDeviceCanBeDefaultSystemDevice, kAudioObjectPropertyScopeInput), 0);
}

static void TestSupportedStreamFormats(void)
{
    UInt32 dataSize = 0;
    AudioStreamRangedDescription descriptions[2];
    memset(descriptions, 0, sizeof(descriptions));

    EXPECT_STATUS(GetSize(kVolDeckHALOutputStreamObjectID, kAudioStreamPropertyAvailableVirtualFormats, kAudioObjectPropertyScopeGlobal, &dataSize), kAudioHardwareNoError);
    EXPECT_UINT32(dataSize, sizeof(descriptions));
    EXPECT_STATUS(GetData(kVolDeckHALOutputStreamObjectID, kAudioStreamPropertyAvailableVirtualFormats, kAudioObjectPropertyScopeGlobal, 0, NULL, sizeof(descriptions), &dataSize, descriptions), kAudioHardwareNoError);
    EXPECT_FLOAT64(descriptions[0].mFormat.mSampleRate, 44100.0);
    EXPECT_FLOAT64(descriptions[1].mFormat.mSampleRate, 48000.0);
    EXPECT_UINT32(descriptions[0].mFormat.mChannelsPerFrame, 2);
    EXPECT_UINT32(descriptions[0].mFormat.mBitsPerChannel, 32);

    Float64 sampleRate = 44100.0;
    EXPECT_STATUS(SetData(kVolDeckHALDeviceObjectID, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, sizeof(sampleRate), &sampleRate), kAudioHardwareNoError);
    EXPECT_FLOAT64(GetFloat64(kVolDeckHALDeviceObjectID, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal), 44100.0);

    sampleRate = 96000.0;
    EXPECT_STATUS(SetData(kVolDeckHALDeviceObjectID, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, sizeof(sampleRate), &sampleRate), kAudioDeviceUnsupportedFormatError);
    EXPECT_FLOAT64(GetFloat64(kVolDeckHALDeviceObjectID, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal), 44100.0);

    AudioStreamBasicDescription streamDescription = VolDeckHALStreamDescription(48000.0);
    EXPECT_STATUS(SetData(kVolDeckHALOutputStreamObjectID, kAudioStreamPropertyVirtualFormat, kAudioObjectPropertyScopeGlobal, sizeof(streamDescription), &streamDescription), kAudioHardwareNoError);
    EXPECT_FLOAT64(GetFloat64(kVolDeckHALDeviceObjectID, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal), 48000.0);

    streamDescription.mChannelsPerFrame = 1;
    EXPECT_STATUS(SetData(kVolDeckHALOutputStreamObjectID, kAudioStreamPropertyVirtualFormat, kAudioObjectPropertyScopeGlobal, sizeof(streamDescription), &streamDescription), kAudioDeviceUnsupportedFormatError);
}

static void TestIOStateAndOperations(void)
{
    EXPECT_UINT32(GetUInt32(kVolDeckHALDeviceObjectID, kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal), 0);

    EXPECT_STATUS(VolDeckHALStartIO(&gVolDeckHALDriverInterfacePointer, kVolDeckHALDeviceObjectID, 1), kAudioHardwareNoError);
    EXPECT_STATUS(VolDeckHALStartIO(&gVolDeckHALDriverInterfacePointer, kVolDeckHALDeviceObjectID, 2), kAudioHardwareNoError);
    EXPECT_UINT32(GetUInt32(kVolDeckHALDeviceObjectID, kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal), 1);

    EXPECT_STATUS(VolDeckHALStopIO(&gVolDeckHALDriverInterfacePointer, kVolDeckHALDeviceObjectID, 1), kAudioHardwareNoError);
    EXPECT_UINT32(GetUInt32(kVolDeckHALDeviceObjectID, kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal), 1);
    EXPECT_STATUS(VolDeckHALStopIO(&gVolDeckHALDriverInterfacePointer, kVolDeckHALDeviceObjectID, 2), kAudioHardwareNoError);
    EXPECT_UINT32(GetUInt32(kVolDeckHALDeviceObjectID, kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal), 0);

    Boolean willDo = false;
    Boolean inPlace = false;
    EXPECT_STATUS(VolDeckHALWillDoIOOperation(&gVolDeckHALDriverInterfacePointer, kVolDeckHALDeviceObjectID, 1, kAudioServerPlugInIOOperationWriteMix, &willDo, &inPlace), kAudioHardwareNoError);
    EXPECT_TRUE(willDo);
    EXPECT_TRUE(inPlace);

    willDo = true;
    inPlace = false;
    EXPECT_STATUS(VolDeckHALWillDoIOOperation(&gVolDeckHALDriverInterfacePointer, kVolDeckHALDeviceObjectID, 1, kAudioServerPlugInIOOperationReadInput, &willDo, &inPlace), kAudioHardwareNoError);
    EXPECT_TRUE(!willDo);
    EXPECT_TRUE(inPlace);

    EXPECT_STATUS(VolDeckHALDoIOOperation(&gVolDeckHALDriverInterfacePointer, kVolDeckHALDeviceObjectID, kVolDeckHALOutputStreamObjectID, 1, kAudioServerPlugInIOOperationWriteMix, 128, NULL, NULL, NULL), kAudioHardwareNoError);
    EXPECT_STATUS(VolDeckHALDoIOOperation(&gVolDeckHALDriverInterfacePointer, kVolDeckHALDeviceObjectID, kVolDeckHALOutputStreamObjectID, 1, kAudioServerPlugInIOOperationReadInput, 128, NULL, NULL, NULL), kAudioHardwareUnsupportedOperationError);
}

static void TestTimestampContract(void)
{
    Float64 sampleTime = 0.0;
    UInt64 hostTime = 0;
    UInt64 seed = 0;

    EXPECT_STATUS(VolDeckHALGetZeroTimeStamp(&gVolDeckHALDriverInterfacePointer, kVolDeckHALDeviceObjectID, 1, &sampleTime, &hostTime, &seed), kAudioHardwareNoError);
    EXPECT_TRUE(hostTime > 0);
    EXPECT_TRUE(seed > 0);
    EXPECT_TRUE(sampleTime >= 0.0);
    EXPECT_STATUS(VolDeckHALGetZeroTimeStamp(&gVolDeckHALDriverInterfacePointer, 999, 1, &sampleTime, &hostTime, &seed), kAudioHardwareBadDeviceError);
}

int main(void)
{
    EXPECT_STATUS(VolDeckHALInitialize(&gVolDeckHALDriverInterfacePointer, NULL), kAudioHardwareNoError);

    TestPluginPublishesOneDevice();
    TestDeviceIsOutputOnly();
    TestDefaultDeviceFlagsStayOutputScoped();
    TestSupportedStreamFormats();
    TestIOStateAndOperations();
    TestTimestampContract();

    if (gFailureCount != 0) {
        fprintf(stderr, "VolDeckHALPluginContractTests failed: %d failure(s)\n", gFailureCount);
        return 1;
    }

    printf("VolDeckHALPluginContractTests passed\n");
    return 0;
}
