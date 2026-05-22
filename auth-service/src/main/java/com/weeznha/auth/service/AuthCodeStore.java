package com.weeznha.auth.service;

import com.weeznha.auth.dto.AuthCodeData;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Component
public class AuthCodeStore {

    private record Entry(UUID userId, String redirectUri, String state, Instant expiresAt) {}

    private final Map<String, Entry> store = new ConcurrentHashMap<>();

    public String store(UUID userId, String redirectUri, String state) {
        String code = UUID.randomUUID().toString().replace("-", "");
        store.put(code, new Entry(userId, redirectUri, state, Instant.now().plus(60, ChronoUnit.SECONDS)));
        return code;
    }

    public Optional<AuthCodeData> consume(String code) {
        Entry entry = store.remove(code);
        if (entry == null || Instant.now().isAfter(entry.expiresAt())) {
            return Optional.empty();
        }
        return Optional.of(new AuthCodeData(entry.userId(), entry.redirectUri(), entry.state()));
    }

    @Scheduled(fixedDelay = 60_000)
    public void cleanup() {
        Instant now = Instant.now();
        store.entrySet().removeIf(e -> now.isAfter(e.getValue().expiresAt()));
    }
}
