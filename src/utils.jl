module Utils

export finallyClose

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

end
