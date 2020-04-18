module Utils

export finallyClose, bounded, TimeoutException

"""
Close the closeable object, ignoring any exceptions that may result. 
"""
function finallyClose(closeAble)
    try
        close(closeAble)
    catch
        # ignore
    end
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
    task = @async put!(result, fn())
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

end
