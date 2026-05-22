package com.weeznha.auth.dto;

import jakarta.validation.constraints.NotBlank;

public record TokenRequest(@NotBlank String code) {}
