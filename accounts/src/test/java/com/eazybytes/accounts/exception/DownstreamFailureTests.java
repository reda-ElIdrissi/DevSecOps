package com.eazybytes.accounts.exception;

import java.net.ConnectException;
import java.net.http.HttpTimeoutException;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.security.oauth2.core.OAuth2AuthorizationException;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.ResourceAccessException;

import static org.assertj.core.api.Assertions.assertThat;

class DownstreamFailureTests {
    @Test
    void mapsDependencyFailuresToPublicStatusCodes() {
        var rejected = new OAuth2AuthorizationException(new OAuth2Error("invalid_client"));
        assertThat(DownstreamFailure.from(rejected).status()).isEqualTo(HttpStatus.BAD_GATEWAY);
        var forbidden = new HttpClientErrorException(HttpStatus.FORBIDDEN);
        assertThat(DownstreamFailure.from(forbidden).status()).isEqualTo(HttpStatus.BAD_GATEWAY);

        var offline = new ResourceAccessException("offline", new ConnectException());
        assertThat(DownstreamFailure.from(offline).status()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        var timedOut = new ResourceAccessException("timeout", new HttpTimeoutException("timeout"));
        assertThat(DownstreamFailure.from(timedOut).status()).isEqualTo(HttpStatus.GATEWAY_TIMEOUT);
    }
}
