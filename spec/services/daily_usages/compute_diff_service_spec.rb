# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyUsages::ComputeDiffService do
  subject(:diff_service) { described_class.new(daily_usage:, previous_daily_usage:) }

  let(:daily_usage) { create(:daily_usage, usage:) }
  let(:previous_daily_usage) { create(:daily_usage, usage: previous_usage) }

  let(:usage) do
    {
      "from_datetime" => "2022-07-01T00:00:00Z",
      "to_datetime" => "2022-07-31T23:59:59Z",
      "issuing_date" => "2022-08-02",
      "lago_invoice_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
      "currency" => "EUR",
      "amount_cents" => 123,
      "taxes_amount_cents" => 20,
      "total_amount_cents" => 143,
      "charges_usage" => [
        {
          "units" => "1.5",
          "events_count" => 11,
          "amount_cents" => 123,
          "amount_currency" => "EUR",
          "charge" => {
            "lago_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
            "charge_model" => "graduated",
            "invoice_display_name" => "Setup"
          },
          "billable_metric" => {
            "lago_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
            "name" => "Storage",
            "code" => "storage",
            "aggregation_type" => "sum_agg"
          },
          "filters" => [
            {
              "units" => "1.4",
              "amount_cents" => 122,
              "events_count" => 10,
              "invoice_display_name" => "AWS eu-east-1",
              "values" => {
                "region" => "us-east-1"
              }
            },
            {
              "units" => "0.1",
              "amount_cents" => 1,
              "events_count" => 1,
              "invoice_display_name" => "AWS eu-east-2",
              "values" => {
                "region" => "us-east-2"
              }
            }
          ],
          "grouped_usage" => [
            {
              "amount_cents" => 101,
              "events_count" => 6,
              "units" => "1.1",
              "grouped_by" => {"country" => nil},
              "filters" => [
                {
                  "units" => "1.0",
                  "amount_cents" => 100,
                  "events_count" => 5,
                  "invoice_display_name" => "AWS eu-east-1",
                  "values" => {
                    "region" => "us-east-1"
                  }
                },
                {
                  "units" => "0.1",
                  "amount_cents" => 1,
                  "events_count" => 1,
                  "invoice_display_name" => "AWS eu-east-2",
                  "values" => {
                    "region" => "us-east-2"
                  }
                }
              ]
            },
            {
              "amount_cents" => 22,
              "events_count" => 5,
              "units" => "0.4",
              "grouped_by" => {"country" => "us"},
              "filters" => [
                {
                  "units" => "0.4",
                  "amount_cents" => 22,
                  "events_count" => 5,
                  "invoice_display_name" => "AWS eu-east-1",
                  "values" => {
                    "region" => "us-east-1"
                  }
                }
              ]
            }
          ]
        }
      ]
    }
  end

  let(:previous_usage) do
    {
      "from_datetime" => "2022-07-01T00:00:00Z",
      "to_datetime" => "2022-07-31T23:59:59Z",
      "issuing_date" => "2022-08-01",
      "lago_invoice_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
      "currency" => "EUR",
      "amount_cents" => 100,
      "taxes_amount_cents" => 15,
      "total_amount_cents" => 115,
      "charges_usage" => [
        {
          "units" => "1.0",
          "events_count" => 5,
          "amount_cents" => 100,
          "amount_currency" => "EUR",
          "charge" => {
            "lago_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
            "charge_model" => "graduated",
            "invoice_display_name" => "Setup"
          },
          "billable_metric" => {
            "lago_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
            "name" => "Storage",
            "code" => "storage",
            "aggregation_type" => "sum_agg"
          },
          "filters" => [
            {
              "units" => "1.0",
              "amount_cents" => 100,
              "events_count" => 5,
              "invoice_display_name" => "AWS eu-east-1",
              "values" => {
                "region" => "us-east-1"
              }
            }
          ],
          "grouped_usage" => [
            {
              "amount_cents" => 100,
              "events_count" => 5,
              "units" => "1.0",
              "grouped_by" => {"country" => nil},
              "filters" => [
                {
                  "units" => "1.0",
                  "amount_cents" => 100,
                  "events_count" => 5,
                  "invoice_display_name" => "AWS eu-east-1",
                  "values" => {
                    "region" => "us-east-1"
                  }
                }
              ]
            }
          ]
        }
      ]
    }
  end

  it "computes the diff between the two daily usages" do
    result = diff_service.call

    expect(result).to be_success
    expect(result.usage_diff).to eq(
      {
        "from_datetime" => "2022-07-01T00:00:00Z",
        "to_datetime" => "2022-07-31T23:59:59Z",
        "issuing_date" => "2022-08-02",
        "lago_invoice_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
        "currency" => "EUR",
        "amount_cents" => 23,
        "taxes_amount_cents" => 5,
        "total_amount_cents" => 28,
        "charges_usage" => [
          {
            "units" => "0.5",
            "events_count" => 6,
            "amount_cents" => 23,
            "amount_currency" => "EUR",
            "charge" => {
              "lago_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
              "charge_model" => "graduated",
              "invoice_display_name" => "Setup"
            },
            "billable_metric" => {
              "lago_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
              "name" => "Storage",
              "code" => "storage",
              "aggregation_type" => "sum_agg"
            },
            "filters" => [
              {
                "units" => "0.4",
                "amount_cents" => 22,
                "events_count" => 5,
                "invoice_display_name" => "AWS eu-east-1",
                "values" => {
                  "region" => "us-east-1"
                }
              },
              {
                "units" => "0.1",
                "amount_cents" => 1,
                "events_count" => 1,
                "invoice_display_name" => "AWS eu-east-2",
                "values" => {
                  "region" => "us-east-2"
                }
              }
            ],
            "grouped_usage" => [
              {
                "amount_cents" => 1,
                "events_count" => 1,
                "units" => "0.1",
                "grouped_by" => {"country" => nil},
                "filters" => [
                  {
                    "units" => "0.0",
                    "amount_cents" => 0,
                    "events_count" => 0,
                    "invoice_display_name" => "AWS eu-east-1",
                    "values" => {
                      "region" => "us-east-1"
                    }
                  },
                  {
                    "units" => "0.1",
                    "amount_cents" => 1,
                    "events_count" => 1,
                    "invoice_display_name" => "AWS eu-east-2",
                    "values" => {
                      "region" => "us-east-2"
                    }
                  }
                ]
              },
              {
                "amount_cents" => 22,
                "events_count" => 5,
                "units" => "0.4",
                "grouped_by" => {"country" => "us"},
                "filters" => [
                  {
                    "units" => "0.4",
                    "amount_cents" => 22,
                    "events_count" => 5,
                    "invoice_display_name" => "AWS eu-east-1",
                    "values" => {
                      "region" => "us-east-1"
                    }
                  }
                ]
              }
            ]
          }
        ]
      }
    )
  end

  context "when the previous daily usage is nil" do
    let(:previous_daily_usage) { nil }

    it "returns the current usage as diff" do
      result = diff_service.call

      expect(result).to be_success
      expect(result.usage_diff).to eq(usage)
    end
  end
end
