package com.eazybytes.loans.security;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.boot.ssl.SslBundles;
import org.springframework.http.client.ClientHttpRequestFactory;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.security.authorization.AuthorizationDecision;
import org.springframework.security.authorization.AuthorizationManager;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtIssuerValidator;
import org.springframework.security.oauth2.jwt.JwtTimestampValidator;
import org.springframework.security.oauth2.jwt.JwtClaimValidator;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jose.jws.SignatureAlgorithm;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.access.intercept.RequestAuthorizationContext;
import org.springframework.security.web.session.DisableEncodeUrlFilter;
import org.springframework.web.client.RestTemplate;

@Configuration(proxyBeanMethods = false)
public class SecurityConfig {

    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        return http
                .addFilterBefore(new RequestAuditFilter(), DisableEncodeUrlFilter.class)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .csrf(csrf -> csrf.disable())
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers(HttpMethod.GET, "/actuator/health").permitAll()
                        .requestMatchers(HttpMethod.GET, "/api/fetch").access(allow("accounts-to-loans", "ROLE_LOANS_READ"))
                        .anyRequest().denyAll())
                .oauth2ResourceServer(oauth -> oauth.jwt(jwt -> jwt.jwtAuthenticationConverter(roleConverter())))
                .build();
    }

    @Bean
    ClientHttpRequestFactory secureTransport(SslBundles sslBundles) {
        var client = HttpClient.newBuilder()
                .sslContext(sslBundles.getBundle("outbound").createSslContext())
                .connectTimeout(Duration.ofSeconds(2))
                .followRedirects(HttpClient.Redirect.NEVER)
                .build();
        var transport = new JdkClientHttpRequestFactory(client);
        transport.setReadTimeout(Duration.ofSeconds(5));
        return transport;
    }

    @Bean
    JwtDecoder jwtDecoder(ClientHttpRequestFactory secureTransport, @Value("${security.issuer}") String issuer) {
        if (!"https".equals(java.net.URI.create(issuer).getScheme())) {
            throw new IllegalArgumentException("The JWT issuer must use HTTPS");
        }
        var decoder = NimbusJwtDecoder.withJwkSetUri(issuer + "/protocol/openid-connect/certs")
                .jwsAlgorithm(SignatureAlgorithm.RS256)
                .restOperations(new RestTemplate(secureTransport))
                .build();
        decoder.setJwtValidator(validator(issuer));
        return decoder;
    }

    static OAuth2TokenValidator<Jwt> validator(String issuer) {
        return new DelegatingOAuth2TokenValidator<>(
                new JwtIssuerValidator(issuer),
                new JwtTimestampValidator(Duration.ofSeconds(30)),
                new JwtClaimValidator<>("exp", expiration -> expiration != null),
                new JwtClaimValidator<String>("sub", subject -> subject != null && !subject.isBlank()),
                new JwtClaimValidator<List<String>>("aud", audience -> audience != null && audience.contains("loans-api")));
    }

    static JwtAuthenticationConverter roleConverter() {
        var allowedRoles = Set.of("SUMMARY_READ", "LOANS_READ", "CARDS_READ", "CARDS_WRITE");
        var converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(jwt -> {
            Object realm = jwt.getClaims().get("realm_access");
            if (!(realm instanceof Map<?, ?> access) || !(access.get("roles") instanceof Collection<?> roles)) {
                return List.of();
            }
            return roles.stream()
                    .filter(String.class::isInstance)
                    .map(String.class::cast)
                    .filter(allowedRoles::contains)
                    .<GrantedAuthority>map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                    .distinct()
                    .toList();
        });
        return converter;
    }

    private static AuthorizationManager<RequestAuthorizationContext> allow(String client, String role) {
        return (authentication, context) -> {
            boolean granted = authentication.get() instanceof JwtAuthenticationToken jwt
                    && client.equals(jwt.getToken().getClaims().get("azp"))
                    && jwt.getAuthorities().stream().anyMatch(authority -> role.equals(authority.getAuthority()));
            if (granted) {
                context.getRequest().setAttribute(RequestAuditFilter.CLIENT_ATTRIBUTE, client);
            }
            return new AuthorizationDecision(granted);
        };
    }
}
