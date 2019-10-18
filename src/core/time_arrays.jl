#
# TimestepVector and TimestepMatrix
#

#
# a.  General
#

# Get a timestep array of type T with N dimensions. Time labels will match those from the time dimension in md
function get_timestep_array(md::ModelDef, T, N, ti, value)
	if isuniform(md)
		first, stepsize = first_and_step(md)
		first === nothing && @warn "get_timestep_array: first === nothing"
        return TimestepArray{FixedTimestep{first, stepsize}, T, N, ti}(value)
    else
        TIMES = (time_labels(md)...,)
        return TimestepArray{VariableTimestep{TIMES}, T, N, ti}(value)
    end
end

# Return the index position of the time dimension in the datumdef or parameter. If there is no time dimension, return nothing
get_time_index_position(dims::Union{Nothing, Array{Symbol}}) = findfirst(isequal(:time), dims)
get_time_index_position(obj::Union{AbstractDatumDef, ArrayModelParameter}) = get_time_index_position(dim_names(obj))

function get_time_index_position(obj::AbstractCompositeComponentDef, comp_name::Symbol, datum_name::Symbol)
	get_time_index_position(dim_names(compdef(obj, comp_name), datum_name))
end

const AnyIndex = Union{Int, Vector{Int}, Tuple, Colon, OrdinalRange}

# Helper function for getindex; throws a MissingException if data is missing, otherwise returns data
function _missing_data_check(data, t)
	if data === missing
		throw(MissingException("Cannot get index; data is missing. You may have tried to access a value in timestep $t that has not yet been computed."))
	else
		return data
	end
end

# Helper function for getindex; throws an error if the TimestepIndex index is out of range of the TimestepArray
function _index_bounds_check(data, dim, t)
	if size(data, dim) < t
		error("TimestepIndex index $t extends beyond bounds of TimestepArray dimension $dim")
	end
end

# Helper function for getindex; throws an error if you index into a N-dimensional TimestepArray with only one index 
# if N > 1; Note that Julia does allow this and returns the column-major value, but this could produce unexpected 
# behavior for users in this case so we do not allow it for now
function _single_index_check(data, idxs)
	num_idxs = length(idxs)
	num_dims = length(size(data))
	if num_idxs < num_dims
		error("Not enough indices provided to index into TimestepArray, $num_idxs provided, $num_dims required")
	end
end

# Helper function for getindex; throws an error if one indexes into a TimestepArray with an integer
function _throw_int_getindex_warning()
	@warn("Indexing with getindex into a TimestepArray with Integer(s) is deprecated, please index with a TimestepIndex(index::Int) instead ie. instead of t[2] use t[TimestepIndex(2)]")
end

# Helper function for setindex; throws an error if one indexes into a TimestepArray with an integer
function _throw_int_setindex_warning()
	@warn("Indexing with setindex into a TimestepArray with Integer(s) is deprecated, please index with a TimestepIndex(index::Int) instead ie. instead of t[2] use t[TimestepIndec(2)]")
end

# Helper macro used by connector
macro allow_missing(expr)
	let e = gensym("e")
		retexpr = quote
			try
				$expr
			catch $e
				if $e isa MissingException
					missing
				else
					rethrow($e)
				end
			end
		end
		return esc(retexpr)
	end
end


# Helper functions for TimestepValue type
function _get_time_value_position(times::Union{Tuple, Array}, ts::TimestepValue{T}) where T
	t = findfirst(isequal.(ts.value, times))
	if t === nothing
		error("cannot use TimestepValue with value $(ts.value), value is not in the TimestepArray")
	end

	t_offset = t + ts.offset
	if t_offset > length(times) 
		error("cannot get TimestepValue offset of $(ts.offset) from value $(ts.value), offset is after the end of the TimestepArray")
	end
	return t_offset
end

#
# b. TimestepVector
#

function Base.getindex(v::TimestepVector{FixedTimestep{FIRST, STEP}, T}, ts::FixedTimestep{FIRST, STEP, LAST}) where {T, FIRST, STEP, LAST}
	data = v.data[ts.t]
	_missing_data_check(data, ts.t)
end

function Base.getindex(v::TimestepVector{VariableTimestep{TIMES}, T}, ts::VariableTimestep{TIMES}) where {T, TIMES}
	data = v.data[ts.t]
	_missing_data_check(data, ts.t)
end

function Base.getindex(v::TimestepVector{FixedTimestep{D_FIRST, STEP}, T}, ts::FixedTimestep{T_FIRST, STEP, LAST}) where {T, D_FIRST, T_FIRST, STEP, LAST}
	t = Int(ts.t + (T_FIRST - D_FIRST) / STEP)
	data = v.data[t]
	_missing_data_check(data, t)
end

function Base.getindex(v::TimestepVector{VariableTimestep{D_TIMES}, T}, ts::VariableTimestep{T_TIMES}) where {T, D_TIMES, T_TIMES}
	t = ts.t + findfirst(isequal(T_TIMES[1]), D_TIMES) - 1
	data = v.data[t]
	_missing_data_check(data, t)
end

function Base.getindex(v::TimestepVector{FixedTimestep{FIRST, STEP}, T_data}, ts::TimestepValue{T_time}) where {T_data, FIRST, STEP, T_time} 
	LAST = FIRST + ((length(v.data)-1) * STEP)
	t = _get_time_value_position([FIRST:STEP:LAST...], ts)
	data = v.data[t]
	_missing_data_check(data, t)
end

function Base.getindex(v::TimestepVector{VariableTimestep{TIMES}, T_data}, ts::TimestepValue{T_time}) where {T_data, TIMES, T_time}
	t = _get_time_value_position(TIMES, ts)
	data = v.data[t]
	_missing_data_check(data, t)
end

function Base.getindex(v::TimestepVector, ts::TimestepIndex) 
	t = ts.index
	_index_bounds_check(v.data, 1, t)
	data = v.data[t]
	_missing_data_check(data, t)
end

function Base.setindex!(v::TimestepVector{FixedTimestep{FIRST, STEP}, T}, val, ts::FixedTimestep{FIRST, STEP, LAST}) where {T, FIRST, STEP, LAST}
	setindex!(v.data, val, ts.t)
end

function Base.setindex!(v::TimestepVector{VariableTimestep{TIMES}, T}, val, ts::VariableTimestep{TIMES}) where {T, TIMES}
	setindex!(v.data, val, ts.t)
end

function Base.setindex!(v::TimestepVector{FixedTimestep{D_FIRST, STEP}, T}, val, ts::FixedTimestep{T_FIRST, STEP, LAST}) where {T, D_FIRST, T_FIRST, STEP, LAST}
	t = Int(ts.t + (T_FIRST - D_FIRST) / STEP)
	setindex!(v.data, val, t)
end

function Base.setindex!(v::TimestepVector{VariableTimestep{D_TIMES}, T}, val, ts::VariableTimestep{T_TIMES}) where {T, D_TIMES, T_TIMES}
	t = ts.t + findfirst(isequal(T_TIMES[1]), D_TIMES) - 1
	setindex!(v.data, val, t)
end

function Base.setindex!(v::TimestepVector, val, ts::TimestepIndex)
	setindex!(v.data, val, ts.index)
end

# int indexing version supports old-style components and internal functions, not
# part of the public API

function Base.getindex(v::TimestepVector{FixedTimestep{FIRST, STEP}, T}, i::AnyIndex) where {T, FIRST, STEP}
	_throw_int_getindex_warning()
	return v.data[i]
end

function Base.getindex(v::TimestepVector{VariableTimestep{TIMES}, T}, i::AnyIndex) where {T, TIMES}
	_throw_int_getindex_warning()
	return v.data[i]
end

function Base.setindex!(v::TimestepVector{FixedTimestep{Start, STEP}, T}, val, i::AnyIndex) where {T, Start, STEP}
	_throw_int_setindex_warning()
	setindex!(v.data, val, i)
end

function Base.setindex!(v::TimestepVector{VariableTimestep{TIMES}, T}, val, i::AnyIndex) where {T, TIMES}
	_throw_int_setindex_warning()
	setindex!(v.data, val, i)
end

function Base.length(v::TimestepVector)
	return length(v.data)
end

Base.lastindex(v::TimestepVector) = length(v)

#
# c. TimestepMatrix
#

function Base.getindex(mat::TimestepMatrix{FixedTimestep{FIRST, STEP}, T, 1}, ts::FixedTimestep{FIRST, STEP, LAST}, idx::AnyIndex) where {T, FIRST, STEP, LAST}
	data = mat.data[ts.t, idx]
	_missing_data_check(data, ts.t)
end

function Base.getindex(mat::TimestepMatrix{VariableTimestep{TIMES}, T, 1}, ts::VariableTimestep{TIMES}, idx::AnyIndex) where {T, TIMES}
	data = mat.data[ts.t, idx]
	_missing_data_check(data, ts.t)
end

function Base.getindex(mat::TimestepMatrix{FixedTimestep{D_FIRST, STEP}, T, 1}, ts::FixedTimestep{T_FIRST, STEP, LAST}, idx::AnyIndex) where {T, D_FIRST, T_FIRST, STEP, LAST}
	t = Int(ts.t + (T_FIRST - D_FIRST) / STEP)
	data = mat.data[t, idx]
	_missing_data_check(data, t)
end

function Base.getindex(mat::TimestepMatrix{VariableTimestep{D_TIMES}, T, 1}, ts::VariableTimestep{T_TIMES}, idx::AnyIndex) where {T, D_TIMES, T_TIMES}
	t = ts.t + findfirst(isequal(T_TIMES[1]), D_TIMES) - 1
	data = mat.data[t, idx]
	_missing_data_check(data, t)
end

function Base.getindex(mat::TimestepMatrix{FixedTimestep{FIRST, STEP}, T, 2}, idx::AnyIndex, ts::FixedTimestep{FIRST, STEP, LAST}) where {T, FIRST, STEP, LAST}
	data = mat.data[idx, ts.t]
	_missing_data_check(data, ts.t)
end

function Base.getindex(mat::TimestepMatrix{VariableTimestep{TIMES}, T, 2}, idx::AnyIndex, ts::VariableTimestep{TIMES}) where {T, TIMES}
	# WAS THIS: data = mat.data[ts.t, idx, ts.t]
	data = mat.data[idx, ts.t]
	_missing_data_check(data, ts.t)
end

function Base.getindex(mat::TimestepMatrix{FixedTimestep{D_FIRST, STEP}, T, 2}, idx::AnyIndex, ts::FixedTimestep{T_FIRST, STEP, LAST}) where {T, D_FIRST, T_FIRST, STEP, LAST}
	t = Int(ts.t + (T_FIRST - D_FIRST) / STEP)
	data = mat.data[idx, t]
	_missing_data_check(data, t)
end

function Base.getindex(mat::TimestepMatrix{VariableTimestep{D_TIMES}, T, 2}, idx::AnyIndex, ts::VariableTimestep{T_TIMES}) where {T, D_TIMES, T_TIMES}
	t = ts.t + findfirst(isequal(T_TIMES[1]), D_TIMES) - 1
	data = mat.data[idx, t]
	_missing_data_check(data, t)
end

function Base.getindex(mat::TimestepMatrix{FixedTimestep{FIRST, STEP}, T_data, 1}, ts::TimestepValue{T_time}, idx::AnyIndex) where {T_data, FIRST, STEP, T_time} 
	LAST = FIRST + ((size(mat.data, 1) - 1) * STEP)
	t = _get_time_value_position([FIRST:STEP:LAST...], ts)
	data = mat.data[t, idx]
	_missing_data_check(data, t)
end

function Base.getindex(mat::TimestepMatrix{VariableTimestep{TIMES}, T_data, 1}, ts::TimestepValue{T_time}, idx::AnyIndex) where {T_data, TIMES, T_time}
	t = _get_time_value_position(TIMES, ts)
	data = mat.data[t, idx]
	_missing_data_check(data, t)
end

function Base.getindex(mat::TimestepMatrix, ts::TimestepIndex, idx::AnyIndex)
	t = ts.index
	_index_bounds_check(mat.data, 1, t)
	data = mat.data[t, idx]
	_missing_data_check(data, t)
end

function Base.getindex(mat::TimestepMatrix{FixedTimestep{FIRST, STEP}, T_data, 2}, idx::AnyIndex, ts::TimestepValue{T_time}) where {T_data, FIRST, STEP, T_time} 
	LAST = FIRST + ((size(mat.data, 2) - 1) * STEP)
	t = _get_time_value_position([FIRST:STEP:LAST...], ts)
	data = mat.data[idx, t]
	_missing_data_check(data, t)
end

function Base.getindex(mat::TimestepMatrix{VariableTimestep{TIMES}, T_data, 2}, idx::AnyIndex, ts::TimestepValue{T_time}) where {T_data, TIMES, T_time}
	t = _get_time_value_position(TIMES, ts)
	data = mat.data[idx, t]
	_missing_data_check(data, t)
end

function Base.getindex(mat::TimestepMatrix, idx::AnyIndex, ts::TimestepIndex)
	t = ts.index
	_index_bounds_check(mat.data, 2, t)
	data = mat.data[idx, t]
	_missing_data_check(data, t)
end

function Base.setindex!(mat::TimestepMatrix{FixedTimestep{FIRST, STEP}, T, 1}, val, ts::FixedTimestep{FIRST, STEP, LAST}, idx::AnyIndex) where {T, FIRST, STEP, LAST}
	setindex!(mat.data, val, ts.t, idx)
end

function Base.setindex!(mat::TimestepMatrix{VariableTimestep{TIMES}, T, 1}, val, ts::VariableTimestep{TIMES}, idx::AnyIndex) where {T, TIMES}
	setindex!(mat.data, val, ts.t, idx)
end

function Base.setindex!(mat::TimestepMatrix{FixedTimestep{D_FIRST, STEP}, T, 1}, val, ts::FixedTimestep{T_FIRST, STEP, LAST}, idx::AnyIndex) where {T, D_FIRST, T_FIRST, STEP, LAST}
	t = Int(ts.t + (T_FIRST - D_FIRST) / STEP)
	setindex!(mat.data, val, t, idx)
end

function Base.setindex!(mat::TimestepMatrix{VariableTimestep{D_TIMES}, T, 1}, val, ts::VariableTimestep{T_TIMES}, idx::AnyIndex) where {T, D_TIMES, T_TIMES}
	t = ts.t + findfirst(isequal(T_TIMES[1]), D_TIMES) - 1
	setindex!(mat.data, val, t, idx)
end

function Base.setindex!(mat::TimestepMatrix{FixedTimestep{FIRST, STEP}, T, 2}, val, idx::AnyIndex, ts::FixedTimestep{FIRST, STEP, LAST}) where {T, FIRST, STEP, LAST}
	setindex!(mat.data, val, idx, ts.t)
end

function Base.setindex!(mat::TimestepMatrix{VariableTimestep{TIMES}, T, 2}, val, idx::AnyIndex, ts::VariableTimestep{TIMES}) where {T, TIMES}
	setindex!(mat.data, val, idx, ts.t)
end

function Base.setindex!(mat::TimestepMatrix{FixedTimestep{D_FIRST, STEP}, T, 2}, val, idx::AnyIndex, ts::FixedTimestep{T_FIRST, STEP, LAST}) where {T, D_FIRST, T_FIRST, STEP, LAST}
	t = Int(ts.t + (T_FIRST - D_FIRST) / STEP)
	setindex!(mat.data, val, idx, t)
end

function Base.setindex!(mat::TimestepMatrix{VariableTimestep{D_TIMES}, T, 2}, val, idx::AnyIndex, ts::VariableTimestep{T_TIMES}) where {T, D_TIMES, T_TIMES}
	t = ts.t + findfirst(isequal(T_TIMES[1]), D_TIMES) - 1
	setindex!(mat.data, val, idx, t)
end

function Base.setindex!(mat::TimestepMatrix, val, idx::AnyIndex, ts::TimestepIndex)
	setindex!(mat.data, val, idx, ts.index)
end

function Base.setindex!(mat::TimestepMatrix, val, ts::TimestepIndex, idx::AnyIndex)
	setindex!(mat.data, val, ts.index, idx)
end

# int indexing version supports old-style components and internal functions, not
# part of the public API

function Base.getindex(mat::TimestepMatrix{FixedTimestep{FIRST, STEP}, T, ti}, idx1::AnyIndex, idx2::AnyIndex) where {T, FIRST, STEP, ti}
	_throw_int_getindex_warning()
	return mat.data[idx1, idx2]
end

function Base.getindex(mat::TimestepMatrix{VariableTimestep{TIMES}, T, ti}, idx1::AnyIndex, idx2::AnyIndex) where {T, TIMES, ti}
	_throw_int_getindex_warning()
	return mat.data[idx1, idx2]
end

function Base.setindex!(mat::TimestepMatrix{FixedTimestep{FIRST, STEP}, T, ti}, val, idx1::Int, idx2::Int) where {T, FIRST, STEP, ti}
	_throw_int_setindex_warning()
	setindex!(mat.data, val, idx1, idx2)
end

function Base.setindex!(mat::TimestepMatrix{FixedTimestep{FIRST, STEP}, T, ti}, val, idx1::AnyIndex, idx2::AnyIndex) where {T, FIRST, STEP, ti}
	_throw_int_setindex_warning()
	mat.data[idx1, idx2] .= val
end

function Base.setindex!(mat::TimestepMatrix{VariableTimestep{TIMES}, T, ti}, val, idx1::Int, idx2::Int) where {T, TIMES, ti}
	_throw_int_setindex_warning()
	setindex!(mat.data, val, idx1, idx2)
end

function Base.setindex!(mat::TimestepMatrix{VariableTimestep{TIMES}, T, ti}, val, idx1::AnyIndex, idx2::AnyIndex) where {T, TIMES, ti}
	_throw_int_setindex_warning()
	mat.data[idx1, idx2] .= val
end

#
# TimestepArray methods
#
function Base.dotview(v::Mimi.TimestepArray, args...)
	# convert any timesteps to their underlying index
	args = map(arg -> (arg isa AbstractTimestep ? arg.t : arg), args)
	Base.dotview(v.data, args...)
end

Base.fill!(obj::TimestepArray, value) = fill!(obj.data, value)

Base.size(obj::TimestepArray) = size(obj.data)

Base.size(obj::TimestepArray, i::Int) = size(obj.data, i)

Base.ndims(obj::TimestepArray{T_ts, T, N, ti}) where {T_ts, T, N, ti} = N

Base.eltype(obj::TimestepArray{T_ts, T, N, ti}) where {T_ts, T, N, ti} = T

first_period(obj::TimestepArray{FixedTimestep{FIRST,STEP}, T, N, ti}) where {FIRST, STEP, T, N, ti} = FIRST
first_period(obj::TimestepArray{VariableTimestep{TIMES}, T, N, ti}) where {TIMES, T, N, ti} = TIMES[1]

last_period(obj::TimestepArray{FixedTimestep{FIRST, STEP}, T, N, ti}) where {FIRST, STEP, T, N, ti} = (FIRST + (size(obj, 1) - 1) * STEP)
last_period(obj::TimestepArray{VariableTimestep{TIMES}, T, N, ti}) where {TIMES, T, N, ti} = TIMES[end]

time_labels(obj::TimestepArray{FixedTimestep{FIRST, STEP}, T, N, ti}) where {FIRST, STEP, T, N, ti} = collect(FIRST:STEP:(FIRST + (size(obj, 1) - 1) * STEP))
time_labels(obj::TimestepArray{VariableTimestep{TIMES}, T, N, ti}) where {TIMES, T, N, ti} = collect(TIMES)

split_indices(idxs, ti) = idxs[1:ti - 1], idxs[ti], idxs[ti + 1:end]

function Base.getindex(arr::TimestepArray{FixedTimestep{FIRST, STEP}, T, N, ti}, idxs::Union{FixedTimestep{FIRST, STEP, LAST}, AnyIndex}...) where {T, N, ti, FIRST, STEP, LAST}
	idxs1, ts, idxs2 = split_indices(idxs, ti)
	return arr.data[idxs1..., ts.t, idxs2...]
end

function Base.getindex(arr::TimestepArray{VariableTimestep{TIMES}, T, N, ti}, idxs::Union{VariableTimestep{TIMES}, AnyIndex}...) where {T, N, ti, TIMES}
	idxs1, ts, idxs2 = split_indices(idxs, ti)
	return arr.data[idxs1..., ts.t, idxs2...]
end

function Base.getindex(arr::TimestepArray{FixedTimestep{D_FIRST, STEP}, T, N, ti}, idxs::Union{FixedTimestep{T_FIRST, STEP, LAST}, AnyIndex}...) where {T, N, ti, D_FIRST, T_FIRST, STEP, LAST}
	idxs1, ts, idxs2 = split_indices(idxs, ti)
	t = Int(ts.t + (FIRST - TIMES[1]) / STEP)
	return arr.data[idxs1..., t, idxs2...]
end

function Base.getindex(arr::TimestepArray{VariableTimestep{D_TIMES}, T, N, ti}, idxs::Union{VariableTimestep{T_TIMES}, AnyIndex}...) where {T, N, ti, D_TIMES, T_TIMES}
	idxs1, ts, idxs2 = split_indices(idxs, ti)
	t = ts.t + findfirst(isequal(T_TIMES[1]), D_TIMES) - 1
	return arr.data[idxs1..., t, idxs2...]
end

function Base.getindex(arr::TimestepArray{FixedTimestep{FIRST, STEP}, T_data, N, ti}, idxs::Union{TimestepValue{T_time}, AnyIndex}...) where {T_data, N, ti, FIRST, STEP, T_time}
	_single_index_check(arr.data, idxs)
	idxs1, ts, idxs2 = split_indices(idxs, ti)
	LAST = FIRST + ((size(arr.data, ti) - 1) * STEP)
	t = _get_time_value_position([FIRST:STEP:LAST...], ts)
	return arr.data[idxs1..., t, idxs2...]
end

function Base.getindex(arr::TimestepArray{VariableTimestep{TIMES}, T_data, N, ti}, idxs::Union{TimestepValue{T_time}, AnyIndex}...) where {T_data, N, ti, TIMES, T_time}
	_single_index_check(arr.data, idxs)
	idxs1, ts, idxs2 = split_indices(idxs, ti)
	t = _get_time_value_position(TIMES, ts)
	return arr.data[idxs1..., t, idxs2...]
end

function Base.getindex(arr::TimestepArray{FixedTimestep{FIRST, STEP}, T, N, ti}, idxs::Union{TimestepIndex, AnyIndex}...) where {T, N, ti, FIRST, STEP}
	_single_index_check(arr.data, idxs)
	idxs1, ts, idxs2 = split_indices(idxs, ti)
	t = ts.index
	_index_bounds_check(arr.data, ti, t)
	return arr.data[idxs1..., t, idxs2...]
end

function Base.getindex(arr::TimestepArray{VariableTimestep{TIMES}, T, N, ti}, idxs::Union{TimestepIndex, AnyIndex}...) where {T, N, ti, TIMES}
	_single_index_check(arr.data, idxs)
	idxs1, ts, idxs2 = split_indices(idxs, ti)
	t = ts.index
	_index_bounds_check(arr.data, ti, t)
	return arr.data[idxs1..., t, idxs2...]
end

function Base.setindex!(arr::TimestepArray{FixedTimestep{FIRST, STEP}, T, N, ti}, val, idxs::Union{FixedTimestep{FIRST, STEP, LAST}, AnyIndex}...) where {T, N, ti, FIRST, STEP, LAST}
	idxs1, ts, idxs2 = split_indices(idxs, ti)
	setindex!(arr.data, val, idxs1..., ts.t, idxs2...)
end

function Base.setindex!(arr::TimestepArray{VariableTimestep{TIMES}, T, N, ti}, val, idxs::Union{VariableTimestep{TIMES}, AnyIndex}...) where {T, N, ti, TIMES}
	idxs1, ts, idxs2 = split_indices(idxs, ti)
	setindex!(arr.data, val, idxs1..., ts.t, idxs2...)
end

function Base.setindex!(arr::TimestepArray{FixedTimestep{D_FIRST, STEP}, T, N, ti}, val, idxs::Union{FixedTimestep{T_FIRST, STEP, LAST}, AnyIndex}...) where {T, N, ti, D_FIRST, T_FIRST, STEP, LAST}
	idxs1, ts, idxs2 = split_indices(idxs, ti)
	t = ts.t + findfirst(isequal(T_FIRST[1]), D_FIRST) - 1
	setindex!(arr.data, val, idxs1..., t, idxs2...)
end

function Base.setindex!(arr::TimestepArray{VariableTimestep{D_TIMES}, T, N, ti}, val, idxs::Union{VariableTimestep{T_TIMES}, AnyIndex}...) where {T, N, ti, D_TIMES, T_TIMES}
	idxs1, ts, idxs2 = split_indices(idxs, ti)
	t = ts.t + findfirst(isequal(T_FIRST[1]), T_TIMES) - 1
	setindex!(arr.data, val, idxs1..., t, idxs2...)
end

function Base.setindex!(arr::TimestepArray{FixedTimestep{FIRST, STEP}, T, N, ti}, val, idxs::Union{TimestepIndex, AnyIndex}...) where {T, N, ti, FIRST, STEP}
	idxs1, ts, idxs2 = split_indices(idxs, ti)
	t = ts.index
	setindex!(arr.data, val, idxs1..., t, idxs2...)
end

function Base.setindex!(arr::TimestepArray{VariableTimestep{TIMES}, T, N, ti}, val, idxs::Union{TimestepIndex, AnyIndex}...) where {T, N, ti, TIMES}
	idxs1, ts, idxs2 = split_indices(idxs, ti)
	t = ts.index
	setindex!(arr.data, val, idxs1..., t, idxs2...)
end

# int indexing version supports old-style components and internal functions, not
# part of the public API; first index is Int or Range, rather than a Timestep

function Base.getindex(arr::TimestepArray{FixedTimestep{FIRST, STEP}, T, N, ti}, idx1::AnyIndex, idx2::AnyIndex, idxs::AnyIndex...) where {T, N, ti, FIRST, STEP}
	_throw_int_getindex_warning()
	return arr.data[idx1, idx2, idxs...]
end

function Base.getindex(arr::TimestepArray{VariableTimestep{TIMES}, T, N, ti}, idx1::AnyIndex, idx2::AnyIndex, idxs::AnyIndex...) where {T, N, ti, TIMES}
	_throw_int_getindex_warning()
	return arr.data[idx1, idx2, idxs...]
end

function Base.setindex!(arr::TimestepArray{FixedTimestep{FIRST, STEP}, T, N, ti}, val, idx1::AnyIndex, idx2::AnyIndex, idxs::AnyIndex...) where {T, N, ti, FIRST, STEP}
	_throw_int_setindex_warning()
	setindex!(arr.data, val, idx1, idx2, idxs...)
end

function Base.setindex!(arr::TimestepArray{VariableTimestep{TIMES}, T, N, ti}, val, idx1::AnyIndex, idx2::AnyIndex, idxs::AnyIndex...) where {T, N, ti, TIMES}
	_throw_int_setindex_warning()
	setindex!(arr.data, val, idx1, idx2, idxs...)
end

"""
	hasvalue(arr::TimestepArray, ts::FixedTimestep)

Return `true` or `false`, `true` if the TimestepArray `arr` contains the Timestep `ts`.
"""
function hasvalue(arr::TimestepArray{FixedTimestep{FIRST, STEP}, T, N, ti}, ts::FixedTimestep{FIRST, STEP, LAST}) where {T, N, ti, FIRST, STEP, LAST}
	return 1 <= ts.t <= size(arr, 1)
end

"""
	hasvalue(arr::TimestepArray, ts::VariableTimestep)

Return `true` or `false`, `true` if the TimestepArray `arr` contains the Timestep `ts`.
"""
function hasvalue(arr::TimestepArray{VariableTimestep{TIMES}, T, N, ti}, ts::VariableTimestep{TIMES}) where {T, N, ti, TIMES}
	return 1 <= ts.t <= size(arr, 1)
end

function hasvalue(arr::TimestepArray{FixedTimestep{D_FIRST, STEP}, T, N, ti}, ts::FixedTimestep{T_FIRST, STEP, LAST}) where {T, N, ti, D_FIRST, T_FIRST, STEP, LAST}
	return D_FIRST <= gettime(ts) <= last_period(arr)
end

function hasvalue(arr::TimestepArray{VariableTimestep{D_FIRST}, T, N, ti}, ts::VariableTimestep{T_FIRST}) where {T, N, ti, T_FIRST, D_FIRST}
	return D_FIRST[1] <= gettime(ts) <= last_period(arr)
end

"""
	hasvalue(arr::TimestepArray, ts::FixedTimestep, idxs::Int...)

Return `true` or `false`, `true` if the TimestepArray `arr` contains the Timestep `ts` within
indices `idxs`. Used when Array and Timestep have different FIRST, validating all dimensions.
"""
function hasvalue(arr::TimestepArray{FixedTimestep{D_FIRST, STEP}, T, N, ti},
	ts::FixedTimestep{T_FIRST, STEP, LAST},
	idxs::Int...) where {T, N, ti, D_FIRST, T_FIRST, STEP, LAST}
	return D_FIRST <= gettime(ts) <= last_period(arr) && all([1 <= idx <= size(arr, i) for (i, idx) in enumerate(idxs)])
end

"""
	hasvalue(arr::TimestepArray, ts::VariableTimestep, idxs::Int...)

Return `true` or `false`, `true` if the TimestepArray `arr` contains the Timestep `ts` within
indices `idxs`. Used when Array and Timestep different TIMES, validating all dimensions.
"""
function hasvalue(arr::TimestepArray{VariableTimestep{D_FIRST}, T, N, ti},
	ts::VariableTimestep{T_FIRST},
	idxs::Int...) where {T, N, ti, D_FIRST, T_FIRST}

	return D_FIRST[1] <= gettime(ts) <= last_period(arr) && all([1 <= idx <= size(arr, i) for (i, idx) in enumerate(idxs)])
end
