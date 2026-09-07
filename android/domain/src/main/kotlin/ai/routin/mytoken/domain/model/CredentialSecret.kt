package ai.routin.mytoken.domain.model

/** Sealed hierarchy of provider credentials, aligned with the secret entries in transfer-schema-v1.json. */
sealed interface CredentialSecret {
    val kind: CredentialKind

    data class BearerToken(val token: String) : CredentialSecret {
        override val kind: CredentialKind get() = CredentialKind.BearerApiKey
    }

    data class ApiKey(val key: String) : CredentialSecret {
        override val kind: CredentialKind get() = CredentialKind.ApiKey
    }

    data class AccessKeyPair(val accessKeyID: String, val secretAccessKey: String) : CredentialSecret {
        override val kind: CredentialKind get() = CredentialKind.AccessKeyPair
    }
}
