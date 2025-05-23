// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.
//
// EEProfInterfaces.inl
//

//
// Inline function implementations for common types used internally in the EE to support
// issuing profiling API callbacks
//

// ======================================================================================

#ifndef __EEPROFINTERFACES_INL__
#define __EEPROFINTERFACES_INL__

#ifndef DACCESS_COMPILE

FORCEINLINE BOOL TrackAllocations()
{
#ifdef PROFILING_SUPPORTED
    return CORProfilerTrackAllocations();
#else
    return FALSE;
#endif // PROFILING_SUPPORTED
}

FORCEINLINE BOOL TrackLargeAllocations()
{
#ifdef PROFILING_SUPPORTED
    return CORProfilerTrackLargeAllocations();
#else
    return FALSE;
#endif // PROFILING_SUPPORTED
}

FORCEINLINE BOOL TrackPinnedAllocations()
{
#ifdef PROFILING_SUPPORTED
    return CORProfilerTrackPinnedAllocations();
#else
    return FALSE;
#endif // PROFILING_SUPPORTED
}

#endif
#endif
