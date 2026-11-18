package com.eazybytes.accounts.security;

import java.io.IOException;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.web.filter.OncePerRequestFilter;

final class RequestAuditFilter extends OncePerRequestFilter {
    static final String CLIENT_ATTRIBUTE = RequestAuditFilter.class.getName() + ".client";
    private static final Logger LOG = LoggerFactory.getLogger(RequestAuditFilter.class);

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        long start = System.nanoTime();
        String correlation = correlationId(request);
        response.setHeader("X-Correlation-ID", correlation);
        try (var ignored = MDC.putCloseable("correlationId", correlation)) {
            try {
                chain.doFilter(request, response);
            } finally {
                int status = response.getStatus();
                if (!"/actuator/health".equals(request.getServletPath())) {
                    LOG.info("correlationId={} client={} decision={} status={} durationMs={}", correlation,
                            request.getAttribute(CLIENT_ATTRIBUTE), decision(status), status,
                            TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start));
                }
            }
        }
    }

    private static String decision(int status) {
        return status == 401 || status == 403 ? "denied" : "allowed";
    }

    private static String correlationId(HttpServletRequest request) {
        return UUID.randomUUID().toString();
    }
}
