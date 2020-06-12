module Utils

using Base
export closeAll, readAvailable, bounded, TimeoutException, compact, identity, groupBy, maxBy

function closeAll(closeables)
    for closeable in closeables
        try
            close(closeable)
        catch ex
            @error "Error during close" exception = (ex, stacktrace(catch_backtrace()))            
        end
    end
end

"""
Reads all available messages on the `Channel`, returning an array
"""
function readAvailable(channel::Channel)
    messages = []
    while isready(channel)
        message = take!(channel)
        push!(messages, message)
    end
    messages
end

"""
An exception thrown if a block invoked with `bounded` did
not complete in the specified time.
"""
struct TimeoutException <: Exception
    timeout
end

"""
Execute the provided expression `fn` in a separate task,
waiting at most `timeout` seconds (using `sleep`). If
the task does not complete in the alloted time, then
abort the task and throw a `TimeoutException` to the
caller of this function.
"""
function bounded(fn, timeout)
    result = Channel(1)
    task = @async begin
        put!(result, fn())
    end
    timer = @async begin
        sleep(timeout)
        schedule(task, TimeoutException(timeout),error=true)
    end
    try
        wait(task)
    catch ex
        close(result)
        if isa(ex, TaskFailedException)
            rethrow(ex.task.exception)
        else
            rethrow()
        end
    end
    take!(result)
end

"""
Return an iterator that skips any `nothing` results from the underlying itetator
"""
function compact(itr)
    Iterators.filter(itr) do el
        el !== nothing
    end
end

"""
Simple identity function: returns its arguments
"""
function identity(value)
    value
end

"""
Return a `Dict` whose keys are the unique values of the supplied function `fn`,
and the values are those items in the original collection for which the supplied
function returned that result.
"""
function groupBy(keyFN::Function, collection, valueFn::Function=identity)
    if isempty(collection)
        Dict()
    else
        results = Dict()
        for item in collection
            key = keyFN(item)
            matches = get!(results, key, Vector())
            push!(matches, valueFn(item))
        end
        results
    end
end

"""
Return the item with the maximum value by comparising the value returned by the supplied
function `fn` against other values in the collection using `<`
"""
function maxBy(keyFn::Function, collection, valueFn=identity)
    maxItem = nothing
    maxValue = nothing
    for item in collection
        if maxItem === nothing
            maxItem = item
            maxValue = valueFn(item)
        end
        itemValue = keyFn(item)
        if(maxValue < itemValue)
            maxItem = item
            maxValue = itemValue
        end
    end
    maxItem
end

end
