package com.weeznha.auth.dto;

import java.util.UUID;

public record AuthCodeData(UUID userId, String redirectUri, String state) {}
