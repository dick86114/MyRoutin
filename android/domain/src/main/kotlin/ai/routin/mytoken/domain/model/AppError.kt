package ai.routin.mytoken.domain.model

sealed class AppError(message: String?, cause: Throwable? = null) : Exception(message, cause) {
    class Network(message: String? = null, cause: Throwable? = null) : AppError(message, cause)
    class Authentication(message: String? = null, cause: Throwable? = null) : AppError(message, cause)
    class Storage(message: String? = null, cause: Throwable? = null) : AppError(message, cause)
    class Decode(message: String? = null, cause: Throwable? = null) : AppError(message, cause)
    class Unknown(message: String? = null, cause: Throwable? = null) : AppError(message, cause)
}
