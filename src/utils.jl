module Utils

export finallyClose, printError

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
Print the error including stacktrace on the designated io
"""
function printError(message::String, ex::Exception, errio = stderr)
    @error "$message: $ex"
    showerror(errio, ex)
    for line in stacktrace(catch_backtrace())
        println(errio, line)
    end
end

end
