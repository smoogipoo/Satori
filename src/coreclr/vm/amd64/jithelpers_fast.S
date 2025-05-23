// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

.intel_syntax noprefix
#include "unixasmmacros.inc"
#include "asmconstants.h"

#ifndef FEATURE_SATORI_GC


// Mark start of the code region that we patch at runtime
LEAF_ENTRY JIT_PatchedCodeStart, _TEXT
        ret
LEAF_END JIT_PatchedCodeStart, _TEXT


// There is an even more optimized version of these helpers possible which takes
// advantage of knowledge of which way the ephemeral heap is growing to only do 1/2
// that check (this is more significant in the JIT_WriteBarrier case).
//
// Additionally we can look into providing helpers which will take the src/dest from
// specific registers (like x86) which _could_ (??) make for easier register allocation
// for the JIT64, however it might lead to having to have some nasty code that treats
// these guys really special like... :(.
//
// Version that does the move, checks whether or not it's in the GC and whether or not
// it needs to have it's card updated
//
// void JIT_CheckedWriteBarrier(Object** dst, Object* src)
LEAF_ENTRY JIT_CheckedWriteBarrier, _TEXT

        // When WRITE_BARRIER_CHECK is defined _NotInHeap will write the reference
        // but if it isn't then it will just return.
        //
        // See if this is in GCHeap
        PREPARE_EXTERNAL_VAR g_lowest_address, rax
        cmp     rdi, [rax]
        // jb      LOCAL_LABEL(NotInHeap)
        .byte 0x72, 0x12
        PREPARE_EXTERNAL_VAR g_highest_address, rax
        cmp     rdi, [rax]

        // jnb     LOCAL_LABEL(NotInHeap)
        .byte 0x73, 0x06
        jmp     [rip + C_FUNC(JIT_WriteBarrier_Loc)]

    LOCAL_LABEL(NotInHeap):
        // See comment above about possible AV
        mov     [rdi], rsi
        ret
LEAF_END_MARKED JIT_CheckedWriteBarrier, _TEXT


// This is used by the mechanism to hold either the JIT_WriteBarrier_PreGrow
// or JIT_WriteBarrier_PostGrow code (depending on the state of the GC). It _WILL_
// change at runtime as the GC changes. Initially it should simply be a copy of the
// larger of the two functions (JIT_WriteBarrier_PostGrow) to ensure we have created
// enough space to copy that code in.
.balign 16
LEAF_ENTRY JIT_WriteBarrier, _TEXT
#ifdef _DEBUG
        // In debug builds, this just contains jump to the debug version of the write barrier by default
        jmp C_FUNC(JIT_WriteBarrier_Debug)
#endif

#ifdef FEATURE_USE_SOFTWARE_WRITE_WATCH_FOR_GC_HEAP
        // JIT_WriteBarrier_WriteWatch_PostGrow64

        // Regarding patchable constants:
        // - 64-bit constants have to be loaded into a register
        // - The constants have to be aligned to 8 bytes so that they can be patched easily
        // - The constant loads have been located to minimize NOP padding required to align the constants
        // - Using different registers for successive constant loads helps pipeline better. Should we decide to use a special
        //   non-volatile calling convention, this should be changed to use just one register.

        // Do the move into the GC .  It is correct to take an AV here, the EH code
        // figures out that this came from a WriteBarrier and correctly maps it back
        // to the managed method which called the WriteBarrier (see setup in
        // InitializeExceptionHandling, vm\exceptionhandling.cpp).
        mov     [rdi], rsi

        // Update the write watch table if necessary
        mov     rax, rdi
        movabs  r10, 0xF0F0F0F0F0F0F0F0
        shr     rax, 0xC // SoftwareWriteWatch::AddressToTableByteIndexShift
        NOP_2_BYTE // padding for alignment of constant
        movabs  r11, 0xF0F0F0F0F0F0F0F0
        add     rax, r10
        cmp     byte ptr [rax], 0x0
        .byte 0x75, 0x06
        // jne     LOCAL_LABEL(CheckCardTable)
        mov     byte ptr [rax], 0xFF

        NOP_3_BYTE // padding for alignment of constant

        // Check the lower and upper ephemeral region bounds
    LOCAL_LABEL(CheckCardTable):
        cmp     rsi, r11
        .byte 0x72,0x3D
        // jb      LOCAL_LABEL(Exit)

        NOP_3_BYTE // padding for alignment of constant

        movabs  r10, 0xF0F0F0F0F0F0F0F0

        cmp     rsi, r10
        .byte 0x73,0x2B
        // jae     LOCAL_LABEL(Exit)

        nop // padding for alignment of constant

        movabs  rax, 0xF0F0F0F0F0F0F0F0

        // Touch the card table entry, if not already dirty.
        shr     rdi, 0x0B
        cmp     byte ptr [rdi + rax], 0xFF
        .byte 0x75, 0x02
        // jne     LOCAL_LABEL(UpdateCardTable)
        REPRET

    LOCAL_LABEL(UpdateCardTable):
        mov     byte ptr [rdi + rax], 0xFF

#ifdef FEATURE_MANUALLY_MANAGED_CARD_BUNDLES
        NOP_2_BYTE // padding for alignment of constant
        shr     rdi, 0x0A

        movabs  rax, 0xF0F0F0F0F0F0F0F0
        cmp     byte ptr [rdi + rax], 0xFF

        .byte 0x75, 0x02
        // jne     LOCAL_LABEL(UpdateCardBundle_WriteWatch_PostGrow64)
        REPRET

    LOCAL_LABEL(UpdateCardBundle_WriteWatch_PostGrow64):
        mov     byte ptr [rdi + rax], 0xFF
#endif

        ret

    .balign 16
    LOCAL_LABEL(Exit):
        REPRET

        NOP_3_BYTE
        NOP_3_BYTE
        NOP_3_BYTE
        NOP_3_BYTE
        NOP_3_BYTE

        NOP_3_BYTE
        NOP_3_BYTE
        NOP_3_BYTE
        NOP_3_BYTE
        NOP_3_BYTE

        NOP_3_BYTE
        NOP_3_BYTE
        NOP_3_BYTE
        NOP_3_BYTE
        NOP_3_BYTE

        NOP_3_BYTE
        NOP_3_BYTE
        NOP_3_BYTE
        NOP_3_BYTE
        NOP_3_BYTE

#else
        // JIT_WriteBarrier_PostGrow64

        // Do the move into the GC .  It is correct to take an AV here, the EH code
        // figures out that this came from a WriteBarrier and correctly maps it back
        // to the managed method which called the WriteBarrier (see setup in
        // InitializeExceptionHandling, vm\exceptionhandling.cpp).
        mov     [rdi], rsi

        NOP_3_BYTE // padding for alignment of constant

        // Can't compare a 64 bit immediate, so we have to move them into a
        // register.  Values of these immediates will be patched at runtime.
        // By using two registers we can pipeline better.  Should we decide to use
        // a special non-volatile calling convention, this should be changed to
        // just one.

        movabs  rax, 0xF0F0F0F0F0F0F0F0

        // Check the lower and upper ephemeral region bounds
        cmp     rsi, rax
        // jb      LOCAL_LABEL(Exit)
        .byte 0x72, 0x36

        nop // padding for alignment of constant

        movabs  r8, 0xF0F0F0F0F0F0F0F0

        cmp     rsi, r8
        // jae     LOCAL_LABEL(Exit)
        .byte 0x73, 0x26

        nop // padding for alignment of constant

        movabs  rax, 0xF0F0F0F0F0F0F0F0

        // Touch the card table entry, if not already dirty.
        shr     rdi, 0Bh
        cmp     byte ptr [rdi + rax], 0FFh
        .byte 0x75, 0x02
        // jne     LOCAL_LABEL(UpdateCardTable)
        REPRET

    LOCAL_LABEL(UpdateCardTable):
        mov     byte ptr [rdi + rax], 0FFh

#ifdef FEATURE_MANUALLY_MANAGED_CARD_BUNDLES
        NOP_6_BYTE // padding for alignment of constant

        movabs  rax, 0xF0F0F0F0F0F0F0F0

        // Touch the card bundle, if not already dirty.
        // rdi is already shifted by 0xB, so shift by 0xA more
        shr     rdi, 0x0A
        cmp     byte ptr [rdi + rax], 0FFh

        .byte 0x75, 0x02
        // jne     LOCAL_LABEL(UpdateCardBundle)
        REPRET

    LOCAL_LABEL(UpdateCardBundle):
        mov     byte ptr [rdi + rax], 0FFh
#endif

        ret

    .balign 16
    LOCAL_LABEL(Exit):
        REPRET
#endif

    // make sure this is bigger than any of the others
    .balign 16
        nop
LEAF_END_MARKED JIT_WriteBarrier, _TEXT

// Mark start of the code region that we patch at runtime
LEAF_ENTRY JIT_PatchedCodeLast, _TEXT
        ret
LEAF_END JIT_PatchedCodeLast, _TEXT

// JIT_ByRefWriteBarrier has weird semantics, see usage in StubLinkerX86.cpp
//
// Entry:
//   RDI - address of ref-field (assigned to)
//   RSI - address of the data  (source)
//
//   Note: RyuJIT assumes that all volatile registers can be trashed by
//   the CORINFO_HELP_ASSIGN_BYREF helper (i.e. JIT_ByRefWriteBarrier)
//   except RDI and RSI. This helper uses and defines RDI and RSI, so
//   they remain as live GC refs or byrefs, and are not killed.
//
//
//   RCX is trashed
//   RAX is trashed
//   R10 is trashed
//   R11 is trashed on Debug build
// Exit:
//   RDI, RSI are incremented by SIZEOF(LPVOID)
LEAF_ENTRY JIT_ByRefWriteBarrier, _TEXT
        mov     rcx, [rsi]

// If !WRITE_BARRIER_CHECK do the write first, otherwise we might have to do some ShadowGC stuff
#ifndef WRITE_BARRIER_CHECK
        // rcx is [rsi]
        mov     [rdi], rcx
#endif

        // When WRITE_BARRIER_CHECK is defined _NotInHeap will write the reference
        // but if it isn't then it will just return.
        //
        // See if this is in GCHeap
        PREPARE_EXTERNAL_VAR g_lowest_address, rax
        cmp     rdi, [rax]
        jb      LOCAL_LABEL(NotInHeap_ByRefWriteBarrier)
        PREPARE_EXTERNAL_VAR g_highest_address, rax
        cmp     rdi, [rax]
        jnb     LOCAL_LABEL(NotInHeap_ByRefWriteBarrier)

#ifdef WRITE_BARRIER_CHECK
        // **ALSO update the shadow GC heap if that is enabled**
        // Do not perform the work if g_GCShadow is 0
        PREPARE_EXTERNAL_VAR g_GCShadow, rax
        cmp     qword ptr [rax], 0
        je      LOCAL_LABEL(NoShadow_ByRefWriteBarrier)

        // If we end up outside of the heap don't corrupt random memory
        mov     r10, rdi
        PREPARE_EXTERNAL_VAR g_lowest_address, rax
        sub     r10, [rax]
        jb      LOCAL_LABEL(NoShadow_ByRefWriteBarrier)

        // Check that our adjusted destination is somewhere in the shadow gc
        PREPARE_EXTERNAL_VAR g_GCShadow, rax
        add     r10, [rax]
        PREPARE_EXTERNAL_VAR g_GCShadowEnd, rax
        cmp     r10, [rax]
        jnb     LOCAL_LABEL(NoShadow_ByRefWriteBarrier)

        // Write ref into real GC
        mov     [rdi], rcx
        // Write ref into shadow GC
        mov     [r10], rcx

        // Ensure that the write to the shadow heap occurs before the read from
        // the GC heap so that race conditions are caught by INVALIDGCVALUE
        mfence

        // Check that GC/ShadowGC values match
        mov     r11, [rdi]
        mov     rax, [r10]
        cmp     rax, r11
        je      LOCAL_LABEL(DoneShadow_ByRefWriteBarrier)
        movabs  r11, INVALIDGCVALUE
        mov     [r10], r11

        jmp     LOCAL_LABEL(DoneShadow_ByRefWriteBarrier)

    // If we don't have a shadow GC we won't have done the write yet
    LOCAL_LABEL(NoShadow_ByRefWriteBarrier):
        mov     [rdi], rcx

    // If we had a shadow GC then we already wrote to the real GC at the same time
    // as the shadow GC so we want to jump over the real write immediately above.
    // Additionally we know for sure that we are inside the heap and therefore don't
    // need to replicate the above checks.
    LOCAL_LABEL(DoneShadow_ByRefWriteBarrier):
#endif

#ifdef FEATURE_USE_SOFTWARE_WRITE_WATCH_FOR_GC_HEAP
        // Update the write watch table if necessary
        PREPARE_EXTERNAL_VAR g_sw_ww_enabled_for_gc_heap, rax
        cmp     byte ptr [rax], 0x0
        je      LOCAL_LABEL(CheckCardTable_ByRefWriteBarrier)
        mov     rax, rdi
        shr     rax, 0xC // SoftwareWriteWatch::AddressToTableByteIndexShift
        PREPARE_EXTERNAL_VAR g_sw_ww_table, r10
        add     rax, qword ptr [r10]
        cmp     byte ptr [rax], 0x0
        jne     LOCAL_LABEL(CheckCardTable_ByRefWriteBarrier)
        mov     byte ptr [rax], 0xFF
#endif

    LOCAL_LABEL(CheckCardTable_ByRefWriteBarrier):
        // See if we can just quick out
        PREPARE_EXTERNAL_VAR g_ephemeral_low, rax
        cmp     rcx, [rax]
        jb      LOCAL_LABEL(Exit_ByRefWriteBarrier)
        PREPARE_EXTERNAL_VAR g_ephemeral_high, rax
        cmp     rcx, [rax]
        jnb     LOCAL_LABEL(Exit_ByRefWriteBarrier)

        mov     rax, rcx

        PREPARE_EXTERNAL_VAR g_region_shr, rcx
        mov     cl, [rcx]
        test    cl, cl
        je      LOCAL_LABEL(SkipCheck_ByRefWriteBarrier)

        // check if the source is in gen 2 - then it's not an ephemeral pointer
        shr     rax, cl
        PREPARE_EXTERNAL_VAR g_region_to_generation_table, r10
        mov     r10, [r10]
        cmp     byte ptr [rax + r10], 0x82
        je      LOCAL_LABEL(Exit_ByRefWriteBarrier)

        // check if the destination happens to be in gen 0
        mov     rax, rdi
        shr     rax, cl
        cmp     byte ptr [rax + r10], 0
        je      LOCAL_LABEL(Exit_ByRefWriteBarrier)
    LOCAL_LABEL(SkipCheck_ByRefWriteBarrier):

        PREPARE_EXTERNAL_VAR g_card_table, r10
        mov     r10, [r10]

        PREPARE_EXTERNAL_VAR g_region_use_bitwise_write_barrier, rax
        cmp     byte ptr [rax], 0
        je      LOCAL_LABEL(CheckCardTableByte_ByRefWriteBarrier)

        // compute card table bit
        mov     ecx, edi
        mov     al, 1
        shr     ecx, 8
        and     cl, 7
        shl     al, cl

        // move current rdi value into rcx and then increment the pointers
        mov     rcx, rdi
        add     rsi, 0x8
        add     rdi, 0x8

        // Check if we need to update the card table
        // Calc pCardByte
        shr     rcx, 0xB
        // Check if this card table bit is already set
        test    byte ptr [rcx + r10], al
        je      LOCAL_LABEL(SetCardTableBit_ByRefWriteBarrier)
        REPRET

    LOCAL_LABEL(SetCardTableBit_ByRefWriteBarrier):
        lock or byte ptr [rcx + r10], al

        jmp     LOCAL_LABEL(CheckCardBundle_ByRefWriteBarrier)

    LOCAL_LABEL(CheckCardTableByte_ByRefWriteBarrier):
        // move current rdi value into rcx and then increment the pointers
        mov     rcx, rdi
        add     rsi, 0x8
        add     rdi, 0x8

        shr     rcx, 0xB
        cmp     byte ptr [rcx + r10], 0xFF
        jne     LOCAL_LABEL(SetCardTableByte_ByRefWriteBarrier)
        REPRET
    LOCAL_LABEL(SetCardTableByte_ByRefWriteBarrier):
        mov     byte ptr [rcx + r10], 0xFF

    LOCAL_LABEL(CheckCardBundle_ByRefWriteBarrier):

#ifdef FEATURE_MANUALLY_MANAGED_CARD_BUNDLES
        // Shift rcx by 0x0A more to get the card bundle byte (we shifted by 0x0B already)
        shr     rcx, 0x0A

        PREPARE_EXTERNAL_VAR g_card_bundle_table, rax
        add     rcx, [rax]

        // Check if this bundle byte is dirty
        cmp     byte ptr [rcx], 0xFF

        jne     LOCAL_LABEL(UpdateCardBundle_ByRefWriteBarrier)
        REPRET

    LOCAL_LABEL(UpdateCardBundle_ByRefWriteBarrier):
        mov     byte ptr [rcx], 0xFF
#endif

        ret

    .balign 16
    LOCAL_LABEL(NotInHeap_ByRefWriteBarrier):
// If WRITE_BARRIER_CHECK then we won't have already done the mov and should do it here
// If !WRITE_BARRIER_CHECK we want _NotInHeap and _Leave to be the same and have both
// 16 byte aligned.
#ifdef WRITE_BARRIER_CHECK
        // rcx is [rsi]
        mov     [rdi], rcx
#endif
    LOCAL_LABEL(Exit_ByRefWriteBarrier):
        // Increment the pointers before leaving
        add     rdi, 0x8
        add     rsi, 0x8
        ret
LEAF_END_MARKED JIT_ByRefWriteBarrier, _TEXT


#else  //FEATURE_SATORI_GC      ##############################################################################

.macro ALTERNATE_ENTRY Name
        .global C_FUNC(\Name)
C_FUNC(\Name):
.endm

// Mark start of the code region that we patch at runtime
LEAF_ENTRY JIT_PatchedCodeStart, _TEXT
        ret
LEAF_END JIT_PatchedCodeStart, _TEXT


// void JIT_CheckedWriteBarrier(Object** dst, Object* src)
LEAF_ENTRY JIT_CheckedWriteBarrier, _TEXT

     // See if dst is in GCHeap
        PREPARE_EXTERNAL_VAR g_card_bundle_table, rax   // fetch the page byte map
        mov     rax, [rax]
        mov     r8, rdi
        shr     r8, 30                                  // dst page index
        cmp     byte ptr [rax + r8], 0
        jne     C_FUNC(CheckedEntry)

    NotInHeap:
        // See comment above about possible AV
        mov     [rdi], rsi
        ret
LEAF_END_MARKED JIT_CheckedWriteBarrier, _TEXT


//
//   rdi - dest address
//   rsi - object
//
.balign 16
LEAF_ENTRY JIT_WriteBarrier, _TEXT
#ifdef FEATURE_SATORI_EXTERNAL_OBJECTS
    // check if src is in heap
        PREPARE_EXTERNAL_VAR g_card_bundle_table, rax   // fetch the page byte map
        mov     rax, [rax]
    ALTERNATE_ENTRY CheckedEntry
        mov     r8, rsi
        shr     r8, 30                                  //  src page index
        cmp     byte ptr [rax + r8], 0
        je      JustAssign                              // src not in heap
#else
    ALTERNATE_ENTRY CheckedEntry
#endif

    // check for escaping assignment
    // 1) check if we own the source region
        mov     rdx, rsi
        and     rdx, 0xFFFFFFFFFFE00000  // source region
#ifndef FEATURE_SATORI_EXTERNAL_OBJECTS
        jz      JustAssign              // assigning null
#endif
#ifdef TARGET_OSX
        mov     rax,  gs:[0]            // thread tag
#else
        mov     rax,  fs:[0]            // thread tag
#endif
        cmp     qword ptr [rdx], rax     
        jne     AssignAndMarkCards      // not local to this thread

    // 2) check if the src and dst are from the same region
        mov     rax, rdi
        and     rax, 0xFFFFFFFFFFE00000 // target aligned to region
        cmp     rax, rdx
        jnz     RecordEscape            // cross region assignment. definitely escaping

    // 3) check if the target is exposed
        mov     rax, rdi
        and     rax, 0x1FFFFF
        shr     rax, 3
        bt      qword ptr [rdx], rax
        jb      RecordEscape            // target is exposed. record an escape.

    JustAssign:
        mov     [rdi], rsi              // no card marking, src is not a heap object

        // set rdi, rsi per contract with JIT_ByRefWriteBarrier
        add     rdi, 8
        mov     rsi, r10
        ret

    AssignAndMarkCards:
        mov     [rdi], rsi

        // TUNING: barriers in different modes could be separate pieces of code, but barrier switch 
        //         needs to suspend EE, not sure if skipping mode check would worth that much.
        PREPARE_EXTERNAL_VAR g_sw_ww_table, rcx
        mov     r11, [rcx]

        // set rdi per contract with JIT_ByRefWriteBarrier
        mov     rax, rdi
        add     rdi, 8

        // check the barrier state. this must be done after the assignment (in program order)
        // if state == 2 we do not set or dirty cards.
        cmp     r11, 2
        jne     DoCards
        // set rsi per contract with JIT_ByRefWriteBarrier
        mov     rsi, r10
    Exit:
        ret

    DoCards:
    // if same region, just check if barrier is not concurrent
        xor     rsi, rax
        shr     rsi, 21
        // set rsi per contract with JIT_ByRefWriteBarrier
        mov     rsi, r10
        jz      CheckConcurrent         // same region, just check if barrier is not concurrent

    // if src is in gen2/3 and the barrier is not concurrent we do not need to mark cards
        cmp     dword ptr [rdx + 16], 2
        jl     MarkCards

    CheckConcurrent:
    // if concurrent, load card location
        cmp     r11, 0
        je      Exit

    MarkCards:
    // fetch card location for rax  (saved rdi)
        PREPARE_EXTERNAL_VAR g_card_table, r9 
        mov     r9,  [r9]  // fetch the page map
        mov     rdx, rax
        shr     rax, 30
        mov     rax, qword ptr [r9 + rax * 8] // page
        sub     rdx, rax   // offset in page
        mov     r8,  rdx
        shr     rdx, 9     // card offset
        shr     r8,  20    // group index
        lea     r8,  [rax + r8 * 2 + 0x80] // group offset

     // check if concurrent marking is in progress
        cmp     r11, 0
        jne     DirtyCard

     // SETTING CARD
     SetCard:
        cmp     byte ptr [rax + rdx], 0
        jne     Exit
        mov     byte ptr [rax + rdx], 1
     SetGroup:
        cmp     byte ptr [r8], 0
        jne     CardSet
        mov     byte ptr [r8], 1
     SetPage:
        cmp     byte ptr [rax], 0
        jne     CardSet
        mov     byte ptr [rax], 1

     CardSet:
     // check if concurrent marking is still not in progress
        cmp     qword ptr [rcx], 0
        jne     DirtyCard
        ret

     // DIRTYING CARD
     DirtyCard:
        mov     byte ptr [rax + rdx], 4
     DirtyGroup:
        cmp     byte ptr [r8], 4
        je      Exit
        mov     byte ptr [r8], 4
     DirtyPage:
        cmp     byte ptr [rax], 4
        je      Exit
        mov     byte ptr [rax], 4
        ret

    // this is expected to be rare.
    RecordEscape:

    // 4) check if the source is escaped
        mov     rax, rsi
        add     rax, 8                        // escape bit is MT + 1
        and     rax, 0x1FFFFF
        shr     rax, 3
        bt      qword ptr [rdx], rax
        jb      AssignAndMarkCards            // source is already escaped.

        // Align rsp
        mov  r9, rsp
        and  rsp, -16
        sub  rsp, 8

        // save rsp, rdi, rsi, rdx and r10 (possibly preadjusted rsi)
        push r9
        push rdi
        push rsi
        push rdx
        push r10

        // void SatoriRegion::EscapeFn(SatoriObject** dst, SatoriObject* src, SatoriRegion* region)
        call    qword ptr [rdx + 8]

        pop     r10
        pop     rdx
        pop     rsi
        pop     rdi
        pop     rsp
        jmp     AssignAndMarkCards
LEAF_END_MARKED JIT_WriteBarrier, _TEXT


// JIT_ByRefWriteBarrier has weird symantics, see usage in StubLinkerX86.cpp
//
// Entry:
//   RDI - address of ref-field (assigned to)
//   RSI - address of the data  (source)
//   Note: RyuJIT assumes that all volatile registers can be trashed by 
//   the CORINFO_HELP_ASSIGN_BYREF helper (i.e. JIT_ByRefWriteBarrier)
//   except RDI and RSI. This helper uses and defines RDI and RSI, so
//   they remain as live GC refs or byrefs, and are not killed.
// Exit:
//   RDI, RSI are incremented by SIZEOF(LPVOID)
LEAF_ENTRY JIT_ByRefWriteBarrier, _TEXT
        lea     r10, [rsi + 8]
        mov     rsi, [rsi]

     // See if dst is in GCHeap
        PREPARE_EXTERNAL_VAR g_card_bundle_table, rax   // fetch the page byte map
        mov     rax, [rax]

        mov     r8, rdi
        shr     r8, 30                                  // dst page index
        cmp     byte ptr [rax + r8], 0
        jne     C_FUNC(CheckedEntry)

    NotInHeap_ByRefWriteBarrier:
        mov     [rdi], rsi
        add     rdi, 8
        mov     rsi, r10
        ret
LEAF_END_MARKED JIT_ByRefWriteBarrier, _TEXT

// Mark start of the code region that we patch at runtime
LEAF_ENTRY JIT_PatchedCodeLast, _TEXT
        ret
LEAF_END JIT_PatchedCodeLast, _TEXT

#endif  // FEATURE_SATORI_GC



        // When JIT_WriteBarrier is copied into an allocated page,
        // helpers use this global variable to jump to it. This variable is set in InitThreadManager.
        .global C_FUNC(JIT_WriteBarrier_Loc)
#ifdef TARGET_OSX
        .zerofill __DATA,__common,C_FUNC(JIT_WriteBarrier_Loc),8,3
#else
        .data
    C_FUNC(JIT_WriteBarrier_Loc):
        .quad 0
        .text
#endif

// ------------------------------------------------------------------
// __declspec(naked) void F_CALL_CONV JIT_WriteBarrier_Callable(Object **dst, Object* val)
.balign 16
LEAF_ENTRY  JIT_WriteBarrier_Callable, _TEXT
        // JIT_WriteBarrier(Object** dst, Object* src)

        // this will be needed if JIT_WriteBarrier relocated/bashed
        // also will need to update locations for checked and byref jit helpers
        // jmp     [rip + C_FUNC(JIT_WriteBarrier_Loc)]

        jmp     C_FUNC(JIT_WriteBarrier)

LEAF_END JIT_WriteBarrier_Callable, _TEXT


// The following helper will access ("probe") a word on each page of the stack
// starting with the page right beneath rsp down to the one pointed to by r11.
// The procedure is needed to make sure that the "guard" page is pushed down below the allocated stack frame.
// The call to the helper will be emitted by JIT in the function/funclet prolog when large (larger than 0x3000 bytes) stack frame is required.
//
// NOTE: On Linux we must advance the stack pointer as we probe - it is not allowed to access 65535 bytes below rsp.
// Since this helper will modify a value of rsp - it must establish the frame pointer.
//
// See also https://github.com/dotnet/runtime/issues/9899#issue-303331518 for more information.

#define PROBE_PAGE_SIZE 0x1000

LEAF_ENTRY JIT_StackProbe, _TEXT
        // On entry:
        //   r11 - points to the lowest address on the stack frame being allocated (i.e. [InitialSp - FrameSize])
        //   rsp - points to some byte on the last probed page
        // On exit:
        //   r11 - is preserved
        //
        // NOTE: this helper will probe at least one page below the one pointed by rsp.

        push_nonvol_reg rbp
        mov     rbp, rsp
        set_cfa_register rbp, 16

    END_PROLOGUE

        and     rsp, -PROBE_PAGE_SIZE  // rsp points to the **lowest address** on the last probed page
                                       // This is done to make the following loop end condition simpler.

LOCAL_LABEL(ProbeLoop):
        sub     rsp, PROBE_PAGE_SIZE   // rsp points to the lowest address of the **next page** to probe
        test    dword ptr [rsp], eax   // rsp points to the lowest address on the **last probed** page
        cmp     rsp, r11
        jg      LOCAL_LABEL(ProbeLoop) // if (rsp > r11), then we need to probe at least one more page.

        RESET_FRAME_WITH_RBP
        ret

LEAF_END_MARKED JIT_StackProbe, _TEXT

LEAF_ENTRY JIT_ValidateIndirectCall, _TEST
        ret
LEAF_END JIT_ValidateIndirectCall, _TEST

LEAF_ENTRY JIT_DispatchIndirectCall, _TEST
        movabs r10, 0xCDCDCDCDCDCDCDCD // The real helper clobbers these registers, so clobber them too in the fake helper
        movabs r11, 0xCDCDCDCDCDCDCDCD
        rex64 jmp rax
LEAF_END JIT_DispatchIndirectCall, _TEST
