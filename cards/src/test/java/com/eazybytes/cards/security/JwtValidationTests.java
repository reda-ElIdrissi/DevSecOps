package com.eazybytes.cards.security;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPublicKey;
import java.time.Instant;
import java.util.Date;
import java.util.List;
import java.util.Map;
import com.nimbusds.jose.JOSEObjectType;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.RSASSASigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class JwtValidationTests {
    private static final String ISSUER = "https://localhost:8443/realms/eazybank";
    private static KeyPair trusted;
    private static KeyPair other;
    private static NimbusJwtDecoder decoder;

    @BeforeAll
    static void createDecoder() throws Exception {
        var keys = KeyPairGenerator.getInstance("RSA");
        keys.initialize(2048);
        trusted = keys.generateKeyPair();
        other = keys.generateKeyPair();
        decoder = NimbusJwtDecoder.withPublicKey((RSAPublicKey) trusted.getPublic()).build();
        decoder.setJwtValidator(SecurityConfig.validator(ISSUER));
    }

    @Test
    void convertsOnlyRecognizedRealmRolesOnASignedToken() throws Exception {
        var jwt = decoder.decode(sign(claims().build(), trusted));
        var authentication = SecurityConfig.roleConverter().convert(jwt);
        assertThat(authentication.getAuthorities()).extracting(GrantedAuthority::getAuthority)
                .contains("ROLE_CARDS_READ")
                .doesNotContain("ROLE_OTHER", "SCOPE_CARDS_WRITE", "ROLE_CARDS_WRITE");
    }

    @Test
    void rejectsUntrustedSignaturesAndInvalidClaims() throws Exception {
        assertRejected(claims(), other);
        assertRejected(claims().issuer(ISSUER + "-other"), trusted);
        assertRejected(claims().audience("loans-api"), trusted);
        assertRejected(claims().expirationTime(null), trusted);
        assertRejected(claims().expirationTime(Date.from(Instant.now().minusSeconds(60))), trusted);
        assertRejected(claims().notBeforeTime(Date.from(Instant.now().plusSeconds(60))), trusted);
        assertRejected(claims().subject(" "), trusted);
    }

    private static void assertRejected(JWTClaimsSet.Builder claims, KeyPair key) throws Exception {
        String serialized = sign(claims.build(), key);
        assertThatThrownBy(() -> decoder.decode(serialized)).isInstanceOf(JwtException.class);
    }

    private static JWTClaimsSet.Builder claims() {
        return new JWTClaimsSet.Builder().issuer(ISSUER).subject("service-subject")
                .audience("cards-api").expirationTime(Date.from(Instant.now().plusSeconds(120)))
                .claim("realm_access", Map.of("roles", List.of("CARDS_READ", "OTHER")))
                .claim("scope", "CARDS_WRITE");
    }

    private static String sign(JWTClaimsSet claims, KeyPair key) throws Exception {
        var jwt = new SignedJWT(new JWSHeader.Builder(JWSAlgorithm.RS256).type(JOSEObjectType.JWT).build(), claims);
        jwt.sign(new RSASSASigner(key.getPrivate()));
        return jwt.serialize();
    }
}
