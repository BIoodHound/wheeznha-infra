package com.weeznha.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record RegisterRequest(
        @NotBlank String username,
        String email,
        @NotBlank @Size(min = 8) String password,
        String name,
        String redirectUri,
        String state
) {}
