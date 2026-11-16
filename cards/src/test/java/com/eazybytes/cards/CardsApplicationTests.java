package com.eazybytes.cards;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
        "server.ssl.enabled=false",
        "TLS_TRUSTSTORE=file:${java.home}/lib/security/cacerts",
        "TLS_TRUSTSTORE_PASSWORD=changeit",
        "spring.ssl.bundle.jks.outbound.truststore.type=JKS"
})
@AutoConfigureMockMvc
class CardsApplicationTests {
    private static final String MOBILE = "0600000001";

    @Autowired
    private MockMvc mvc;

    @MockitoBean
    private JwtDecoder decoder;

    @Test
    void requiresBothTheClientIdentityAndItsRole() throws Exception {
        when(decoder.decode("wrong-client")).thenReturn(jwt("probe-cards", "CARDS_READ"));
        when(decoder.decode("no-role")).thenReturn(jwt("accounts-to-cards"));
        when(decoder.decode("reader")).thenReturn(jwt("accounts-to-cards", "CARDS_READ"));

        mvc.perform(get("/api/fetch").param("mobileNumber", MOBILE))
                .andExpect(status().isUnauthorized());
        for (String token : List.of("wrong-client", "no-role")) {
            mvc.perform(get("/api/fetch").param("mobileNumber", MOBILE).header("Authorization", "Bearer " + token))
                    .andExpect(status().isForbidden());
        }
        mvc.perform(get("/api/fetch").param("mobileNumber", MOBILE).header("Authorization", "Bearer reader"))
                .andExpect(status().isOk());
        mvc.perform(post("/api/create").param("mobileNumber", MOBILE).header("Authorization", "Bearer reader"))
                .andExpect(status().isForbidden());
        mvc.perform(delete("/api/delete").param("mobileNumber", MOBILE).header("Authorization", "Bearer reader"))
                .andExpect(status().isForbidden());
    }

    @Test
    void allowsTheOperatorToCreateACardOnly() throws Exception {
        when(decoder.decode("operator")).thenReturn(jwt("cards-operator", "CARDS_WRITE"));
        mvc.perform(post("/api/create").param("mobileNumber", "0600000003").header("Authorization", "Bearer operator"))
                .andExpect(status().isCreated());
        mvc.perform(get("/api/fetch").param("mobileNumber", "0600000003").header("Authorization", "Bearer operator"))
                .andExpect(status().isForbidden());
    }

    private static Jwt jwt(String client, String... roles) {
        return Jwt.withTokenValue(client).header("alg", "RS256").subject(client).issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(120)).audience(List.of("cards-api"))
                .claim("azp", client).claim("realm_access", Map.of("roles", List.of(roles))).build();
    }
}
