package com.eazybytes.accounts.exception;

import java.net.SocketTimeoutException;
import java.net.http.HttpTimeoutException;
import org.springframework.http.HttpStatus;
import org.springframework.security.oauth2.core.OAuth2AuthorizationException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClientResponseException;

public final class DownstreamFailure extends RuntimeException {
    private final HttpStatus status;

    public DownstreamFailure(HttpStatus status) {
        super("Downstream request failed");
        this.status = status;
    }

    public HttpStatus status() {
        return status;
    }

    public static DownstreamFailure from(RuntimeException failure) {
        for (Throwable cause = failure; cause != null; cause = cause.getCause()) {
            if (cause instanceof SocketTimeoutException || cause instanceof HttpTimeoutException) {
                return new DownstreamFailure(HttpStatus.GATEWAY_TIMEOUT);
            }
        }
        for (Throwable cause = failure; cause != null; cause = cause.getCause()) {
            if (cause instanceof ResourceAccessException) {
                return new DownstreamFailure(HttpStatus.SERVICE_UNAVAILABLE);
            }
            if (cause instanceof RestClientResponseException response && response.getStatusCode().is5xxServerError()) {
                return new DownstreamFailure(HttpStatus.SERVICE_UNAVAILABLE);
            }
        }
        if (failure instanceof OAuth2AuthorizationException authorization
                && "temporarily_unavailable".equals(authorization.getError().getErrorCode())) {
            return new DownstreamFailure(HttpStatus.SERVICE_UNAVAILABLE);
        }
        return new DownstreamFailure(HttpStatus.BAD_GATEWAY);
    }
}
