package com.eazybytes.accounts;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest(properties = {
        "server.ssl.enabled=false",
        "TLS_TRUSTSTORE=file:${java.home}/lib/security/cacerts",
        "TLS_TRUSTSTORE_PASSWORD=changeit",
        "spring.ssl.bundle.jks.outbound.truststore.type=JKS",
        "ACCOUNTS_LOANS_CLIENT_SECRET=test-loans",
        "ACCOUNTS_CARDS_CLIENT_SECRET=test-cards"
})
class AccountsApplicationTests {

	@Test
	void contextLoads() {
	}

}
