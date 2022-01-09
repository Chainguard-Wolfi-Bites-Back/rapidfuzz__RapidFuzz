# distutils: language=c++
# cython: language_level=3, binding=True, linetrace=True

from libc.stdint cimport uint64_t, int64_t
from libc.stdlib cimport malloc, free
from libc.stddef cimport wchar_t
from libcpp.utility cimport pair
from libcpp cimport bool
from libcpp.utility cimport move
from cpython.object cimport PyObject
from cython.operator cimport dereference
from libcpp.vector cimport vector
from cpython.pycapsule cimport PyCapsule_IsValid, PyCapsule_GetPointer

from rapidfuzz_capi cimport (
    RF_Scorer, RF_StringType, RF_String, RF_Kwargs,
    RF_ScorerFlags, RF_Preprocessor
)

from array import array

cdef extern from "cpp_common.hpp":
    cdef cppclass RF_StringWrapper:
        RF_String string
        PyObject* obj

        RF_StringWrapper()
        RF_StringWrapper(RF_String)
        RF_StringWrapper(RF_String, object)

    cdef cppclass RF_KwargsWrapper:
        RF_Kwargs kwargs

        RF_KwargsWrapper()
        RF_KwargsWrapper(RF_Kwargs)

    cdef cppclass PyObjectWrapper:
        PyObject* obj

        PyObjectWrapper()
        PyObjectWrapper(object)

    void default_string_deinit(RF_String* string) nogil

    int is_valid_string(object py_str) except +
    RF_String convert_string(object py_str)
    void validate_string(object py_str, const char* err) except +

    vector[T] vector_slice[T](const vector[T]& vec, int start, int stop, int step) except +

cdef inline RF_String hash_array(arr) except *:
    # TODO on Cpython this does not require any copies
    cdef RF_String s_proc
    cdef Py_UCS4 typecode = <Py_UCS4>arr.typecode
    s_proc.length = <size_t>len(arr)

    s_proc.data = malloc(s_proc.length * sizeof(uint64_t))

    if s_proc.data == NULL:
        raise MemoryError

    try:
        # ignore signed/unsigned, since it is not relevant in any of the algorithms
        if typecode in {'b', 'B'}: # signed/unsigned char
            s_proc.kind = RF_StringType.RF_UINT64
            for i in range(s_proc.length):
                (<uint64_t*>s_proc.data)[i] = <uint64_t>arr[i]
        elif typecode == 'u': # 'u' wchar_t
            s_proc.kind = RF_StringType.RF_UINT64
            for i in range(s_proc.length):
                (<uint64_t*>s_proc.data)[i] = <uint64_t><Py_UCS4>arr[i]
        elif typecode in {'h', 'H'}: #  signed/unsigned short
            s_proc.kind = RF_StringType.RF_UINT64
            for i in range(s_proc.length):
                (<uint64_t*>s_proc.data)[i] = <uint64_t>arr[i]
        elif typecode in {'i', 'I'}: # signed/unsigned int
            s_proc.kind = RF_StringType.RF_UINT64
            for i in range(s_proc.length):
                (<uint64_t*>s_proc.data)[i] = <uint64_t>arr[i]
        elif typecode in {'l', 'L'}: # signed/unsigned long
            s_proc.kind = RF_StringType.RF_UINT64
            for i in range(s_proc.length):
                (<uint64_t*>s_proc.data)[i] = <uint64_t>arr[i]
        elif typecode in {'q', 'Q'}: # signed/unsigned long long
            s_proc.kind = RF_StringType.RF_UINT64
            for i in range(s_proc.length):
                (<uint64_t*>s_proc.data)[i] = <uint64_t>arr[i]
        else: # float/double are hashed
            s_proc.kind = RF_StringType.RF_UINT64
            for i in range(s_proc.length):
                (<uint64_t*>s_proc.data)[i] = <uint64_t>hash(arr[i])
    except Exception as e:
        free(s_proc.data)
        s_proc.data = NULL
        raise

    s_proc.dtor = default_string_deinit
    return s_proc


cdef inline RF_String hash_sequence(seq) except *:
    cdef RF_String s_proc
    s_proc.length = <size_t>len(seq)

    s_proc.data = malloc(s_proc.length * sizeof(uint64_t))

    if s_proc.data == NULL:
        raise MemoryError

    try:
        s_proc.kind = RF_StringType.RF_UINT64
        for i in range(s_proc.length):
            elem = seq[i]
            # this is required so e.g. a list of char can be compared to a string
            if isinstance(elem, str) and len(elem) == 1:
                (<uint64_t*>s_proc.data)[i] = <uint64_t><Py_UCS4>elem
            else:
                (<uint64_t*>s_proc.data)[i] = <uint64_t>hash(elem)
    except Exception as e:
        free(s_proc.data)
        s_proc.data = NULL
        raise

    s_proc.dtor = default_string_deinit
    return s_proc

cdef inline RF_String conv_sequence(seq) except *:
    if is_valid_string(seq):
        return move(convert_string(seq))
    elif isinstance(seq, array):
        return move(hash_array(seq))
    else:
        return move(hash_sequence(seq))

cdef inline double get_score_cutoff_f64(score_cutoff, const RF_ScorerFlags* scorer_flags) except *:
    worst_score = dereference(scorer_flags).worst_score.f64
    optimal_score = dereference(scorer_flags).optimal_score.f64
    c_score_cutoff = worst_score
    
    if score_cutoff is not None:
        c_score_cutoff = score_cutoff
        if optimal_score > worst_score:
            # e.g. 0.0 - 100.0
            if c_score_cutoff < worst_score or c_score_cutoff > optimal_score:
                raise TypeError(f"score_cutoff has to be in the range of {worst_score} - {optimal_score}")
        else:
            # e.g. DBL_MAX - 0
            if c_score_cutoff > worst_score or c_score_cutoff < optimal_score:
                raise TypeError(f"score_cutoff has to be in the range of {optimal_score} - {worst_score}")
    
    return c_score_cutoff

cdef inline uint64_t get_score_cutoff_u64(score_cutoff, const RF_ScorerFlags* scorer_flags) except *:
    worst_score = dereference(scorer_flags).worst_score.u64
    optimal_score = dereference(scorer_flags).optimal_score.u64
    c_score_cutoff = worst_score
    
    if score_cutoff is not None:
        c_score_cutoff = score_cutoff
        if optimal_score > worst_score:
            # e.g. 0.0 - 100.0
            if c_score_cutoff < worst_score or c_score_cutoff > optimal_score:
                raise TypeError(f"score_cutoff has to be in the range of {worst_score} - {optimal_score}")
        else:
            # e.g. DBL_MAX - 0
            if c_score_cutoff > worst_score or c_score_cutoff < optimal_score:
                raise TypeError(f"score_cutoff has to be in the range of {optimal_score} - {worst_score}")

    return c_score_cutoff

cdef inline int64_t get_score_cutoff_i64(score_cutoff, const RF_ScorerFlags* scorer_flags) except *:
    worst_score = dereference(scorer_flags).worst_score.i64
    optimal_score = dereference(scorer_flags).optimal_score.i64
    c_score_cutoff = worst_score
    
    if score_cutoff is not None:
        c_score_cutoff = score_cutoff
        if optimal_score > worst_score:
            # e.g. 0.0 - 100.0
            if c_score_cutoff < worst_score or c_score_cutoff > optimal_score:
                raise TypeError(f"score_cutoff has to be in the range of {worst_score} - {optimal_score}")
        else:
            # e.g. DBL_MAX - 0
            if c_score_cutoff > worst_score or c_score_cutoff < optimal_score:
                raise TypeError(f"score_cutoff has to be in the range of {optimal_score} - {worst_score}")
    
    return c_score_cutoff