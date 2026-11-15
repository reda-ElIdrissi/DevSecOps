package com.eazybytes.loans;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest(properties = {
        "server.ssl.enabled=false",
        "TLS_TRUSTSTORE=file:${java.home}/lib/security/cacerts",
        "TLS_TRUSTSTORE_PASSWORD=changeit",
        "spring.ssl.bundle.jks.outbound.truststore.type=JKS"
})
class LoansApplicationTests {

	@Test
	void contextLoads() {
	}

}
