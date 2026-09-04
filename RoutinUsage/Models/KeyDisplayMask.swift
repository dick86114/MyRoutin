enum KeyDisplayMask {
    static func masked(suffix: String) -> String {
        guard
            suffix.count == KeyCredentialPolicy.minimumVisibleSuffixLength,
            !KeyCredentialPolicy.isLegacyShortSecretSuffix(suffix)
        else {
            return "plan-••••"
        }
        return "plan-••••\(suffix)"
    }
}
