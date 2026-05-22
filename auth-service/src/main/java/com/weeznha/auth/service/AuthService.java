package com.weeznha.auth.service;

import com.weeznha.auth.config.JwtService;
import com.weeznha.auth.dto.*;
import com.weeznha.auth.model.Role;
import com.weeznha.auth.model.User;
import com.weeznha.auth.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final AuthCodeStore authCodeStore;

    public Object login(LoginRequest request) {
        User user = userRepository.findByUsername(request.username())
                .orElseThrow(() -> new BadCredentialsException("Invalid credentials"));

        if (!passwordEncoder.matches(request.password(), user.getPassword())) {
            throw new BadCredentialsException("Invalid credentials");
        }

        return buildResponse(user, request.redirectUri(), request.state());
    }

    public Object register(RegisterRequest request) {
        if (userRepository.existsByUsername(request.username())) {
            throw new IllegalArgumentException("Username already taken");
        }
        if (request.email() != null && !request.email().isBlank()
                && userRepository.existsByEmail(request.email())) {
            throw new IllegalArgumentException("Email already registered");
        }

        User user = User.builder()
                .id(UUID.randomUUID())
                .username(request.username())
                .email(request.email())
                .password(passwordEncoder.encode(request.password()))
                .name(request.name())
                .role(Role.USER)
                .build();

        userRepository.save(user);
        return buildResponse(user, request.redirectUri(), request.state());
    }

    public TokenResponse exchangeCode(String code) {
        AuthCodeData data = authCodeStore.consume(code)
                .orElseThrow(() -> new IllegalArgumentException("Invalid or expired code"));

        User user = userRepository.findById(data.userId())
                .orElseThrow(() -> new IllegalStateException("User not found"));

        return toTokenResponse(user);
    }

    public TokenResponse refresh(String refreshToken) {
        if (!jwtService.isTokenValid(refreshToken)) {
            throw new IllegalArgumentException("Invalid or expired refresh token");
        }

        UUID userId = jwtService.extractUserId(refreshToken);
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new IllegalStateException("User not found"));

        return toTokenResponse(user);
    }

    private Object buildResponse(User user, String redirectUri, String state) {
        if (redirectUri != null && !redirectUri.isBlank()) {
            String code = authCodeStore.store(user.getId(), redirectUri, state);
            return new AuthCodeResponse(code, redirectUri, state);
        }
        return toTokenResponse(user);
    }

    private TokenResponse toTokenResponse(User user) {
        return new TokenResponse(
                jwtService.generateAccessToken(user),
                jwtService.generateRefreshToken(user),
                86400,
                "Bearer"
        );
    }
}
