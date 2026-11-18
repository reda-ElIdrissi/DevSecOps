package com.eazybytes.accounts.service.client;

import java.net.URI;
import java.time.Duration;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.ClientHttpRequestFactory;
import org.springframework.http.converter.FormHttpMessageConverter;
import org.springframework.security.oauth2.client.AuthorizedClientServiceOAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.ClientCredentialsOAuth2AuthorizedClientProvider;
import org.springframework.security.oauth2.client.InMemoryOAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.OAuth2AuthorizeRequest;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.endpoint.OAuth2AccessTokenResponseClient;
import org.springframework.security.oauth2.client.endpoint.OAuth2ClientCredentialsGrantRequest;
import org.springframework.security.oauth2.client.endpoint.RestClientClientCredentialsTokenResponseClient;
import org.springframework.security.oauth2.client.http.OAuth2ErrorResponseErrorHandler;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.client.registration.InMemoryClientRegistrationRepository;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.ClientAuthenticationMethod;
import org.springframework.security.oauth2.core.http.converter.OAuth2AccessTokenResponseHttpMessageConverter;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.support.RestClientAdapter;
import org.springframework.web.service.invoker.HttpServiceProxyFactory;

@Configuration(proxyBeanMethods = false)
class DownstreamClients {
    private static final Logger LOG = LoggerFactory.getLogger(DownstreamClients.class);
    private static final String LOANS = "accounts-to-loans";
    private static final String CARDS = "accounts-to-cards";

    @Bean
    OAuth2AuthorizedClientManager downstreamAuthorization(
            ClientHttpRequestFactory secureTransport,
            @Value("${security.issuer}") String issuer,
            @Value("${ACCOUNTS_LOANS_CLIENT_SECRET}") String loansSecret,
            @Value("${ACCOUNTS_CARDS_CLIENT_SECRET}") String cardsSecret) {
        String tokenUri = httpsUri(issuer + "/protocol/openid-connect/token");
        var registrations = new InMemoryClientRegistrationRepository(
                registration(LOANS, loansSecret, tokenUri), registration(CARDS, cardsSecret, tokenUri));
        var manager = new AuthorizedClientServiceOAuth2AuthorizedClientManager(
                registrations, new InMemoryOAuth2AuthorizedClientService(registrations));
        var provider = new ClientCredentialsOAuth2AuthorizedClientProvider();
        provider.setClockSkew(Duration.ofSeconds(15));
        var tokenClient = new RestClientClientCredentialsTokenResponseClient();
        tokenClient.setRestClient(RestClient.builder()
                .requestFactory(secureTransport)
                .configureMessageConverters(converters -> {
                    converters.addCustomConverter(new FormHttpMessageConverter());
                    converters.addCustomConverter(new OAuth2AccessTokenResponseHttpMessageConverter());
                })
                .defaultStatusHandler(new OAuth2ErrorResponseErrorHandler())
                .build());
        OAuth2AccessTokenResponseClient<OAuth2ClientCredentialsGrantRequest> measuredTokenClient = request -> {
            var response = tokenClient.getTokenResponse(request);
            LOG.info("correlationId={} issuedTokenFor={}", MDC.get("correlationId"),
                    request.getClientRegistration().getRegistrationId());
            return response;
        };
        provider.setAccessTokenResponseClient(measuredTokenClient);
        manager.setAuthorizedClientProvider(provider);
        return manager;
    }

    @Bean
    LoansClient loansClient(ClientHttpRequestFactory secureTransport, OAuth2AuthorizedClientManager manager,
                            @Value("${LOANS_BASE_URL:https://localhost:8090}") String url) {
        return proxy(LoansClient.class, url, LOANS, secureTransport, manager);
    }

    @Bean
    CardsClient cardsClient(ClientHttpRequestFactory secureTransport, OAuth2AuthorizedClientManager manager,
                            @Value("${CARDS_BASE_URL:https://localhost:9000}") String url) {
        return proxy(CardsClient.class, url, CARDS, secureTransport, manager);
    }

    private static ClientRegistration registration(String id, String secret, String tokenUri) {
        return ClientRegistration.withRegistrationId(id)
                .clientId(id)
                .clientSecret(secret)
                .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
                .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS)
                .tokenUri(tokenUri)
                .build();
    }

    private static <T> T proxy(Class<T> type, String baseUrl, String registration,
                               ClientHttpRequestFactory transport, OAuth2AuthorizedClientManager manager) {
        var authorization = OAuth2AuthorizeRequest.withClientRegistrationId(registration).principal("accounts").build();
        var restClient = RestClient.builder()
                .requestFactory(transport)
                .baseUrl(httpsUri(baseUrl))
                .requestInterceptor((request, body, execution) -> {
                    String token;
                    synchronized (authorization) {
                        token = manager.authorize(authorization).getAccessToken().getTokenValue();
                    }
                    request.getHeaders().setBearerAuth(token);
                    String correlation = MDC.get("correlationId");
                    if (correlation != null) {
                        request.getHeaders().set("X-Correlation-ID", correlation);
                    }
                    return execution.execute(request, body);
                })
                .build();
        return HttpServiceProxyFactory.builderFor(RestClientAdapter.create(restClient)).build().createClient(type);
    }

    private static String httpsUri(String value) {
        URI uri = URI.create(value);
        if (!"https".equals(uri.getScheme()) || uri.getHost() == null || uri.getUserInfo() != null) {
            throw new IllegalArgumentException("An HTTPS service URL is required");
        }
        return value;
    }
}
