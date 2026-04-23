# frozen_string_literal: true

require "net/http"
require "json"

module PricingImports
  class AnalyzeService < BaseService
    Result = BaseResult[:proposed_plan]

    ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
    ANTHROPIC_VERSION = "2023-06-01"
    DEFAULT_MODEL = "claude-sonnet-4-5"
    MAX_CHARS = 200_000

    SYSTEM_PROMPT = <<~PROMPT
      You translate messy customer pricing files into a Lago billing configuration.

      Return ONLY a single JSON object (no prose, no markdown fences). Shape:

      {
        "billable_metrics": [
          { "code": "tokens_1m", "name": "Tokens (1M)", "aggregation_type": "sum_agg", "field_name": "tokens", "recurring": false }
        ],
        "plans": [
          { "code": "ai_studio_advanced_1y", "name": "AI Studio - Advanced - 1Y", "interval": "monthly",
            "amount_cents": 125000, "amount_currency": "EUR", "pay_in_advance": false,
            "charges": [
              { "billable_metric_code": "tokens_1m", "charge_model": "percentage", "pay_in_advance": false, "properties": { "rate": "35" } }
            ]
          }
        ],
        "notes": "Short explanation of modelling choices",
        "ambiguities": [ { "item": "PAI-2001", "question": "Euro 0 plan with usage passthrough?" } ]
      }

      Rules:
      - aggregation_type MUST be one of: count_agg, sum_agg, max_agg, unique_count_agg, weighted_sum_agg, latest_agg, custom_agg
      - charge_model MUST be one of: standard, graduated, package, percentage, volume, graduated_percentage
      - interval MUST be one of: weekly, monthly, yearly, quarterly, semiannual
      - amount_cents is an integer in the smallest currency unit (e.g. EUR 1250.00 -> 125000)
      - code must be lowercase snake_case, unique within its kind
      - If a row is a subscription price (fixed monthly fee), model it as a plan.amount_cents - NOT as a charge
      - If a row is a usage/consumption price (tokens, GPU hours, API calls), create a billable_metric and attach a charge referencing it via billable_metric_code
      - For a "% of consumption" price, use charge_model "percentage" with properties.rate as a string like "35"
      - For a flat per-unit price, use charge_model "standard" with properties.amount as a string like "0.22"
      - pay_in_advance defaults to false on both plans and charges unless clearly stated otherwise
      - Prefer creating ONE billable metric per physical unit of measurement (Token, GPU Hour, Instance) and REUSING it across plans
      - Include ambiguities for anything you are uncertain about - the user will review and edit before anything is created
    PROMPT

    def initialize(file_text:, source_filename:)
      @file_text = file_text.to_s[0, MAX_CHARS]
      @source_filename = source_filename
      super
    end

    def call
      api_key = ENV["ANTHROPIC_API_KEY"]
      if api_key.blank?
        return result.service_failure!(code: "missing_api_key", message: "ANTHROPIC_API_KEY env var is not set")
      end

      payload = anthropic_request(api_key)
      text = extract_text(payload)
      proposed = parse_json(text)

      result.proposed_plan = proposed
      result
    rescue => e
      result.service_failure!(code: "anthropic_call_failed", message: e.message)
    end

    private

    attr_reader :file_text, :source_filename

    def anthropic_request(api_key)
      uri = URI(ANTHROPIC_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 120

      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"] = "application/json"
      req["x-api-key"] = api_key
      req["anthropic-version"] = ANTHROPIC_VERSION
      req.body = {
        model: ENV.fetch("ANTHROPIC_MODEL", DEFAULT_MODEL),
        max_tokens: 16_000,
        system: SYSTEM_PROMPT,
        messages: [
          {
            role: "user",
            content: "File: #{source_filename}\n\n---\n\n#{file_text}\n\n---\n\nReturn the JSON proposal now."
          }
        ]
      }.to_json

      res = http.request(req)
      unless res.is_a?(Net::HTTPSuccess)
        raise "Anthropic API returned #{res.code}: #{res.body[0, 500]}"
      end

      JSON.parse(res.body)
    end

    def extract_text(payload)
      block = (payload["content"] || []).find { |b| b["type"] == "text" }
      raise "Anthropic response contained no text block" unless block

      block["text"]
    end

    def parse_json(text)
      stripped = text.strip
      if (m = stripped.match(/\A```(?:json)?\s*\n(.*?)\n```\z/m))
        stripped = m[1]
      end

      start_idx = stripped.index("{")
      end_idx = stripped.rindex("}")
      raise "Could not locate a JSON object in Claude response" if start_idx.nil? || end_idx.nil?

      JSON.parse(stripped[start_idx..end_idx])
    end
  end
end
