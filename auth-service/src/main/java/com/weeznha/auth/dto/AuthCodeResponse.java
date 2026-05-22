package com.weeznha.auth.dto;

public record AuthCodeResponse(
        String code,
        String redirectUri,
        String state
) {}
