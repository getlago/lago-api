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

  context "when a charge is deleted between snapshots" do
    let(:charge_a_id) { "aaaa1111-1a90-1a90-1a90-1a901a901a90" }
    let(:charge_c_id) { "cccc3333-1a90-1a90-1a90-1a901a901a90" }

    let(:usage) do
      {
        "from_datetime" => "2022-07-01T00:00:00Z",
        "to_datetime" => "2022-07-31T23:59:59Z",
        "issuing_date" => "2022-08-02",
        "lago_invoice_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
        "currency" => "EUR",
        "amount_cents" => 150,
        "taxes_amount_cents" => 15,
        "total_amount_cents" => 165,
        "charges_usage" => [
          {
            "units" => "1.5",
            "events_count" => 8,
            "amount_cents" => 150,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => charge_a_id, "charge_model" => "standard", "invoice_display_name" => "API Calls"},
            "billable_metric" => {"lago_id" => "bm-a", "name" => "API Calls", "code" => "api_calls", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
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
        "amount_cents" => 300,
        "taxes_amount_cents" => 30,
        "total_amount_cents" => 330,
        "charges_usage" => [
          {
            "units" => "1.0",
            "events_count" => 5,
            "amount_cents" => 100,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => charge_a_id, "charge_model" => "standard", "invoice_display_name" => "API Calls"},
            "billable_metric" => {"lago_id" => "bm-a", "name" => "API Calls", "code" => "api_calls", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
          },
          {
            "units" => "2.0",
            "events_count" => 10,
            "amount_cents" => 200,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => charge_c_id, "charge_model" => "standard", "invoice_display_name" => "Storage"},
            "billable_metric" => {"lago_id" => "bm-c", "name" => "Storage", "code" => "storage", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
          }
        ]
      }
    end

    it "derives top-level amounts from per-charge diffs, ignoring the deleted charge" do
      result = diff_service.call

      expect(result).to be_success

      diff = result.usage_diff

      expect(diff["amount_cents"]).to eq(50)
      expect(diff["taxes_amount_cents"]).to eq(5)
      expect(diff["total_amount_cents"]).to eq(55)

      expect(diff["charges_usage"].size).to eq(1)
      charge_a_diff = diff["charges_usage"].first
      expect(charge_a_diff["charge"]["lago_id"]).to eq(charge_a_id)
      expect(charge_a_diff["amount_cents"]).to eq(50)
      expect(charge_a_diff["units"]).to eq("0.5")
      expect(charge_a_diff["events_count"]).to eq(3)
    end
  end

  context "when a new charge is added between snapshots" do
    let(:charge_a_id) { "aaaa1111-1a90-1a90-1a90-1a901a901a90" }
    let(:charge_b_id) { "bbbb2222-1a90-1a90-1a90-1a901a901a90" }

    let(:usage) do
      {
        "from_datetime" => "2022-07-01T00:00:00Z",
        "to_datetime" => "2022-07-31T23:59:59Z",
        "issuing_date" => "2022-08-02",
        "lago_invoice_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
        "currency" => "EUR",
        "amount_cents" => 200,
        "taxes_amount_cents" => 20,
        "total_amount_cents" => 220,
        "charges_usage" => [
          {
            "units" => "1.5",
            "events_count" => 8,
            "amount_cents" => 150,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => charge_a_id, "charge_model" => "standard", "invoice_display_name" => "API Calls"},
            "billable_metric" => {"lago_id" => "bm-a", "name" => "API Calls", "code" => "api_calls", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
          },
          {
            "units" => "0.5",
            "events_count" => 3,
            "amount_cents" => 50,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => charge_b_id, "charge_model" => "standard", "invoice_display_name" => "Storage"},
            "billable_metric" => {"lago_id" => "bm-b", "name" => "Storage", "code" => "storage", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
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
        "taxes_amount_cents" => 10,
        "total_amount_cents" => 110,
        "charges_usage" => [
          {
            "units" => "1.0",
            "events_count" => 5,
            "amount_cents" => 100,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => charge_a_id, "charge_model" => "standard", "invoice_display_name" => "API Calls"},
            "billable_metric" => {"lago_id" => "bm-a", "name" => "API Calls", "code" => "api_calls", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
          }
        ]
      }
    end

    it "includes the new charge's full amount in the diff" do
      result = diff_service.call

      expect(result).to be_success

      diff = result.usage_diff

      expect(diff["amount_cents"]).to eq(100)
      expect(diff["taxes_amount_cents"]).to eq(10)
      expect(diff["total_amount_cents"]).to eq(110)

      expect(diff["charges_usage"].size).to eq(2)

      charge_a_diff = diff["charges_usage"].find { |cu| cu["charge"]["lago_id"] == charge_a_id }
      expect(charge_a_diff["amount_cents"]).to eq(50)
      expect(charge_a_diff["units"]).to eq("0.5")
      expect(charge_a_diff["events_count"]).to eq(3)

      charge_b_diff = diff["charges_usage"].find { |cu| cu["charge"]["lago_id"] == charge_b_id }
      expect(charge_b_diff["amount_cents"]).to eq(50)
      expect(charge_b_diff["units"]).to eq("0.5")
      expect(charge_b_diff["events_count"]).to eq(3)
    end
  end

  context "when all charges are replaced between snapshots" do
    let(:charge_a_id) { "aaaa1111-1a90-1a90-1a90-1a901a901a90" }
    let(:charge_b_id) { "bbbb2222-1a90-1a90-1a90-1a901a901a90" }

    let(:usage) do
      {
        "from_datetime" => "2022-07-01T00:00:00Z",
        "to_datetime" => "2022-07-31T23:59:59Z",
        "issuing_date" => "2022-08-02",
        "lago_invoice_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
        "currency" => "EUR",
        "amount_cents" => 80,
        "taxes_amount_cents" => 8,
        "total_amount_cents" => 88,
        "charges_usage" => [
          {
            "units" => "2.0",
            "events_count" => 4,
            "amount_cents" => 80,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => charge_b_id, "charge_model" => "standard", "invoice_display_name" => "Storage"},
            "billable_metric" => {"lago_id" => "bm-b", "name" => "Storage", "code" => "storage", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
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
        "taxes_amount_cents" => 10,
        "total_amount_cents" => 110,
        "charges_usage" => [
          {
            "units" => "1.0",
            "events_count" => 5,
            "amount_cents" => 100,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => charge_a_id, "charge_model" => "standard", "invoice_display_name" => "API Calls"},
            "billable_metric" => {"lago_id" => "bm-a", "name" => "API Calls", "code" => "api_calls", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
          }
        ]
      }
    end

    it "does not deduct any previous taxes since no charges overlap" do
      result = diff_service.call

      diff = result.usage_diff

      expect(diff["amount_cents"]).to eq(80)
      expect(diff["taxes_amount_cents"]).to eq(8)
      expect(diff["total_amount_cents"]).to eq(88)

      charge_b_diff = diff["charges_usage"].first
      expect(charge_b_diff["charge"]["lago_id"]).to eq(charge_b_id)
      expect(charge_b_diff["amount_cents"]).to eq(80)
    end
  end

  context "when previous amount_cents is zero" do
    let(:charge_a_id) { "aaaa1111-1a90-1a90-1a90-1a901a901a90" }

    let(:usage) do
      {
        "from_datetime" => "2022-07-01T00:00:00Z",
        "to_datetime" => "2022-07-31T23:59:59Z",
        "issuing_date" => "2022-08-02",
        "lago_invoice_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
        "currency" => "EUR",
        "amount_cents" => 50,
        "taxes_amount_cents" => 5,
        "total_amount_cents" => 55,
        "charges_usage" => [
          {
            "units" => "1.0",
            "events_count" => 3,
            "amount_cents" => 50,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => charge_a_id, "charge_model" => "standard", "invoice_display_name" => "API Calls"},
            "billable_metric" => {"lago_id" => "bm-a", "name" => "API Calls", "code" => "api_calls", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
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
        "amount_cents" => 0,
        "taxes_amount_cents" => 0,
        "total_amount_cents" => 0,
        "charges_usage" => [
          {
            "units" => "0.0",
            "events_count" => 0,
            "amount_cents" => 0,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => charge_a_id, "charge_model" => "standard", "invoice_display_name" => "API Calls"},
            "billable_metric" => {"lago_id" => "bm-a", "name" => "API Calls", "code" => "api_calls", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
          }
        ]
      }
    end

    it "skips ratio calculation and deducts full previous taxes" do
      result = diff_service.call

      diff = result.usage_diff

      expect(diff["amount_cents"]).to eq(50)
      expect(diff["taxes_amount_cents"]).to eq(5)
      expect(diff["total_amount_cents"]).to eq(55)
    end
  end

  context "when charges are both added and deleted between snapshots" do
    let(:charge_a_id) { "aaaa1111-1a90-1a90-1a90-1a901a901a90" }
    let(:charge_b_id) { "bbbb2222-1a90-1a90-1a90-1a901a901a90" }
    let(:charge_c_id) { "cccc3333-1a90-1a90-1a90-1a901a901a90" }

    let(:usage) do
      {
        "from_datetime" => "2022-07-01T00:00:00Z",
        "to_datetime" => "2022-07-31T23:59:59Z",
        "issuing_date" => "2022-08-02",
        "lago_invoice_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
        "currency" => "EUR",
        "amount_cents" => 250,
        "taxes_amount_cents" => 25,
        "total_amount_cents" => 275,
        "charges_usage" => [
          {
            "units" => "2.0",
            "events_count" => 8,
            "amount_cents" => 200,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => charge_a_id, "charge_model" => "standard", "invoice_display_name" => "API Calls"},
            "billable_metric" => {"lago_id" => "bm-a", "name" => "API Calls", "code" => "api_calls", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
          },
          {
            "units" => "1.0",
            "events_count" => 2,
            "amount_cents" => 50,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => charge_c_id, "charge_model" => "standard", "invoice_display_name" => "Bandwidth"},
            "billable_metric" => {"lago_id" => "bm-c", "name" => "Bandwidth", "code" => "bandwidth", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
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
        "amount_cents" => 300,
        "taxes_amount_cents" => 30,
        "total_amount_cents" => 330,
        "charges_usage" => [
          {
            "units" => "1.0",
            "events_count" => 5,
            "amount_cents" => 100,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => charge_a_id, "charge_model" => "standard", "invoice_display_name" => "API Calls"},
            "billable_metric" => {"lago_id" => "bm-a", "name" => "API Calls", "code" => "api_calls", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
          },
          {
            "units" => "3.0",
            "events_count" => 10,
            "amount_cents" => 200,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => charge_b_id, "charge_model" => "standard", "invoice_display_name" => "Storage"},
            "billable_metric" => {"lago_id" => "bm-b", "name" => "Storage", "code" => "storage", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
          }
        ]
      }
    end

    it "prorates taxes based on overlapping charge ratio and includes new charge fully" do
      # Previous: A(100) + B(200) = 300, taxes = 30
      # Current:  A(200) + C(50)  = 250, taxes = 25
      # Only charge A overlaps: 100/300 = 1/3 of previous taxes = 10
      # Diff amount: A(200-100) + C(50) = 150
      # Diff taxes: 25 - 10 = 15
      result = diff_service.call

      diff = result.usage_diff

      expect(diff["amount_cents"]).to eq(150)
      expect(diff["taxes_amount_cents"]).to eq(15)
      expect(diff["total_amount_cents"]).to eq(165)

      expect(diff["charges_usage"].size).to eq(2)

      charge_a_diff = diff["charges_usage"].find { |cu| cu["charge"]["lago_id"] == charge_a_id }
      expect(charge_a_diff["amount_cents"]).to eq(100)
      expect(charge_a_diff["units"]).to eq("1.0")
      expect(charge_a_diff["events_count"]).to eq(3)

      charge_c_diff = diff["charges_usage"].find { |cu| cu["charge"]["lago_id"] == charge_c_id }
      expect(charge_c_diff["amount_cents"]).to eq(50)
      expect(charge_c_diff["units"]).to eq("1.0")
      expect(charge_c_diff["events_count"]).to eq(2)
    end
  end

  context "when previous_daily_usage is not provided" do
    subject(:diff_service) { described_class.new(daily_usage:) }

    let(:subscription) { create(:subscription) }
    let(:from_datetime) { Time.zone.parse("2022-07-01T00:00:00Z") }
    let(:to_datetime) { Time.zone.parse("2022-07-31T23:59:59Z") }

    let(:daily_usage) do
      create(:daily_usage, subscription:, from_datetime:, to_datetime:, usage_date: Date.new(2022, 7, 15), usage:)
    end

    let(:usage) do
      {
        "from_datetime" => "2022-07-01T00:00:00Z",
        "to_datetime" => "2022-07-31T23:59:59Z",
        "issuing_date" => "2022-08-02",
        "lago_invoice_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
        "currency" => "EUR",
        "amount_cents" => 150,
        "taxes_amount_cents" => 0,
        "total_amount_cents" => 150,
        "charges_usage" => [
          {
            "units" => "1.5",
            "events_count" => 8,
            "amount_cents" => 150,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => "aaaa1111-1a90-1a90-1a90-1a901a901a90", "charge_model" => "standard", "invoice_display_name" => "API Calls"},
            "billable_metric" => {"lago_id" => "bm-a", "name" => "API Calls", "code" => "api_calls", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
          }
        ]
      }
    end

    let(:previous_usage_data) do
      {
        "from_datetime" => "2022-07-01T00:00:00Z",
        "to_datetime" => "2022-07-31T23:59:59Z",
        "issuing_date" => "2022-08-01",
        "lago_invoice_id" => "1a901a90-1a90-1a90-1a90-1a901a901a90",
        "currency" => "EUR",
        "amount_cents" => 100,
        "taxes_amount_cents" => 0,
        "total_amount_cents" => 100,
        "charges_usage" => [
          {
            "units" => "1.0",
            "events_count" => 5,
            "amount_cents" => 100,
            "amount_currency" => "EUR",
            "charge" => {"lago_id" => "aaaa1111-1a90-1a90-1a90-1a901a901a90", "charge_model" => "standard", "invoice_display_name" => "API Calls"},
            "billable_metric" => {"lago_id" => "bm-a", "name" => "API Calls", "code" => "api_calls", "aggregation_type" => "sum_agg"},
            "filters" => [],
            "grouped_usage" => []
          }
        ]
      }
    end

    before do
      create(
        :daily_usage,
        subscription:,
        from_datetime:,
        to_datetime:,
        usage_date: Date.new(2022, 7, 14),
        usage: previous_usage_data
      )
    end

    it "automatically finds the previous daily usage from the database" do
      result = diff_service.call

      diff = result.usage_diff

      expect(diff["amount_cents"]).to eq(50)
      expect(diff["charges_usage"].first["amount_cents"]).to eq(50)
      expect(diff["charges_usage"].first["units"]).to eq("0.5")
      expect(diff["charges_usage"].first["events_count"]).to eq(3)
    end

    context "when there is a gap of several days without events" do
      # Simulates: events on day 4, none on days 5-8, events again on day 9 of the same billing
      # period. The previous daily_usage lives 5 days back, not at usage_date - 1.day, so the
      # diff must look further back than yesterday to avoid double-counting the day 4 events.
      let(:daily_usage) do
        create(:daily_usage, subscription:, from_datetime:, to_datetime:, usage_date: Date.new(2022, 7, 9), usage:)
      end

      before do
        # Wipe the default previous_daily_usage at 2022-07-14 created above; here we only want
        # the 2022-07-04 row to exist as the prior snapshot.
        DailyUsage.where(subscription:).where.not(usage_date: Date.new(2022, 7, 4)).delete_all

        create(
          :daily_usage,
          subscription:,
          from_datetime:,
          to_datetime:,
          usage_date: Date.new(2022, 7, 4),
          usage: previous_usage_data
        )
      end

      it "diffs against the latest prior daily usage in the same billing period" do
        diff = diff_service.call.usage_diff

        expect(diff["amount_cents"]).to eq(50)
        expect(diff["charges_usage"].first["amount_cents"]).to eq(50)
        expect(diff["charges_usage"].first["units"]).to eq("0.5")
        expect(diff["charges_usage"].first["events_count"]).to eq(3)
      end
    end

    context "when a prior daily usage exists in a different billing period" do
      # The prior daily_usage belongs to the previous billing period (different from_datetime /
      # to_datetime); it must NOT be used as the diff baseline for the current period's first
      # row — that row should fall back to "full usage".
      let(:daily_usage) do
        create(:daily_usage, subscription:, from_datetime:, to_datetime:, usage_date: Date.new(2022, 7, 1), usage:)
      end

      before do
        DailyUsage.where(subscription:).where.not(id: daily_usage.id).delete_all

        create(
          :daily_usage,
          subscription:,
          from_datetime: from_datetime - 1.month,
          to_datetime: to_datetime - 1.month,
          usage_date: Date.new(2022, 6, 30),
          usage: previous_usage_data
        )
      end

      it "returns the full current usage instead of diffing across periods" do
        expect(diff_service.call.usage_diff).to eq(usage)
      end
    end
  end

  context "when the previous daily usage is nil" do
    let(:previous_daily_usage) { nil }

    it "returns the current usage as diff" do
      result = diff_service.call

      expect(result).to be_success
      expect(result.usage_diff).to eq(usage)
    end
  end

  describe "presentation_breakdowns" do
    def charge_usage(lago_id:, presentation_breakdowns: [], filters: [], grouped_usage: [])
      {
        "charge" => {"lago_id" => lago_id},
        "units" => "0.0",
        "events_count" => 0,
        "amount_cents" => 0,
        "filters" => filters,
        "grouped_usage" => grouped_usage,
        "presentation_breakdowns" => presentation_breakdowns
      }
    end

    def grouped_usage(grouped_by:, presentation_breakdowns:, filters: [])
      {
        "grouped_by" => grouped_by,
        "units" => "0.0",
        "events_count" => 0,
        "amount_cents" => 0,
        "filters" => filters,
        "presentation_breakdowns" => presentation_breakdowns
      }
    end

    def filter_usage(values:, presentation_breakdowns: [])
      {
        "values" => values,
        "units" => "0.0",
        "events_count" => 0,
        "amount_cents" => 0,
        "invoice_display_name" => nil,
        "presentation_breakdowns" => presentation_breakdowns
      }
    end

    def usage_payload(charges_usage:)
      {
        "amount_cents" => 0,
        "taxes_amount_cents" => 0,
        "charges_usage" => charges_usage
      }
    end

    context "when a presentation breakdown exists in both snapshots" do
      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.1"},
                {"presentation_by" => {"region" => "eu"}, "units" => "0.4"}
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.0"}
              ]
            )
          ]
        )
      end

      it "diffs non-grouped usage presentation_breakdowns by presentation_by" do
        result = diff_service.call

        expect(result).to be_success

        diff_charge = result.usage_diff.fetch("charges_usage").first
        expect(diff_charge.fetch("presentation_breakdowns")).to eq(
          [
            {"presentation_by" => {"region" => "us"}, "units" => "0.1"},
            {"presentation_by" => {"region" => "eu"}, "units" => "0.4"}
          ]
        )
      end
    end

    context "when presentation breakdowns are nested under grouped_usage" do
      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              grouped_usage: [
                grouped_usage(
                  grouped_by: {"country" => nil},
                  presentation_breakdowns: [
                    {"presentation_by" => {"region" => "us-east-1"}, "units" => "1.0"},
                    {"presentation_by" => {"region" => "us-east-2"}, "units" => "0.1"}
                  ]
                ),
                grouped_usage(
                  grouped_by: {"country" => "us"},
                  presentation_breakdowns: [
                    {"presentation_by" => {"region" => "us-east-1"}, "units" => "0.4"}
                  ]
                )
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              grouped_usage: [
                grouped_usage(
                  grouped_by: {"country" => nil},
                  presentation_breakdowns: [
                    {"presentation_by" => {"region" => "us-east-1"}, "units" => "1.0"}
                  ]
                )
              ]
            )
          ]
        )
      end

      it "diffs grouped_usage presentation_breakdowns by presentation_by" do
        result = diff_service.call
        expect(result).to be_success

        charge_diff = result.usage_diff.fetch("charges_usage").first
        grouped_nil = charge_diff.fetch("grouped_usage").find { |gu| gu["grouped_by"] == {"country" => nil} }

        expect(grouped_nil.fetch("presentation_breakdowns")).to eq(
          [
            {"presentation_by" => {"region" => "us-east-1"}, "units" => "0.0"},
            {"presentation_by" => {"region" => "us-east-2"}, "units" => "0.1"}
          ]
        )

        grouped_us = charge_diff.fetch("grouped_usage").find { |gu| gu["grouped_by"] == {"country" => "us"} }
        expect(grouped_us.fetch("presentation_breakdowns")).to eq(
          [
            {"presentation_by" => {"region" => "us-east-1"}, "units" => "0.4"}
          ]
        )
      end
    end

    context "when a charge is deleted between snapshots" do
      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.5"},
                {"presentation_by" => {"region" => "eu"}, "units" => "0.2"}
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.0"}
              ]
            ),
            charge_usage(
              lago_id: "charge-c",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "2.0"}
              ]
            )
          ]
        )
      end

      it "diffs presentation_breakdowns only for the overlapping charge" do
        diff = diff_service.call.usage_diff
        charge_a = diff.fetch("charges_usage").first

        expect(charge_a.fetch("presentation_breakdowns")).to eq(
          [
            {"presentation_by" => {"region" => "us"}, "units" => "0.5"},
            {"presentation_by" => {"region" => "eu"}, "units" => "0.2"}
          ]
        )
      end
    end

    context "when a new charge is added between snapshots" do
      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.5"}
              ]
            ),
            charge_usage(
              lago_id: "charge-b",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "eu"}, "units" => "0.5"}
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.0"}
              ]
            )
          ]
        )
      end

      it "keeps the new charge presentation_breakdowns unchanged" do
        diff = diff_service.call.usage_diff

        charge_a = diff.fetch("charges_usage").find { |cu| cu.dig("charge", "lago_id") == "charge-a" }
        expect(charge_a.fetch("presentation_breakdowns")).to eq(
          [{"presentation_by" => {"region" => "us"}, "units" => "0.5"}]
        )

        charge_b = diff.fetch("charges_usage").find { |cu| cu.dig("charge", "lago_id") == "charge-b" }
        expect(charge_b.fetch("presentation_breakdowns")).to eq(
          [{"presentation_by" => {"region" => "eu"}, "units" => "0.5"}]
        )
      end
    end

    context "when all charges are replaced between snapshots" do
      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-b",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "2.0"}
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.0"}
              ]
            )
          ]
        )
      end

      it "does not diff presentation_breakdowns when there is no overlap" do
        diff = diff_service.call.usage_diff
        charge_b = diff.fetch("charges_usage").first

        expect(charge_b.fetch("presentation_breakdowns")).to eq(
          [{"presentation_by" => {"region" => "us"}, "units" => "2.0"}]
        )
      end
    end

    context "when charges are both added and deleted between snapshots" do
      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "2.0"}
              ]
            ),
            charge_usage(
              lago_id: "charge-c",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "eu"}, "units" => "1.0"}
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.0"}
              ]
            ),
            charge_usage(
              lago_id: "charge-b",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "3.0"}
              ]
            )
          ]
        )
      end

      it "diffs presentation_breakdowns for the common charge and keeps new ones" do
        diff = diff_service.call.usage_diff

        charge_a = diff.fetch("charges_usage").find { |cu| cu.dig("charge", "lago_id") == "charge-a" }
        expect(charge_a.fetch("presentation_breakdowns")).to eq(
          [{"presentation_by" => {"region" => "us"}, "units" => "1.0"}]
        )

        charge_c = diff.fetch("charges_usage").find { |cu| cu.dig("charge", "lago_id") == "charge-c" }
        expect(charge_c.fetch("presentation_breakdowns")).to eq(
          [{"presentation_by" => {"region" => "eu"}, "units" => "1.0"}]
        )
      end
    end

    context "when filters in charges_usage contain presentation_breakdowns" do
      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              filters: [
                filter_usage(
                  values: {"region" => "us"},
                  presentation_breakdowns: [
                    {"presentation_by" => {"provider" => "aws"}, "units" => "1.1"},
                    {"presentation_by" => {"provider" => "gcp"}, "units" => "0.4"}
                  ]
                )
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              filters: [
                filter_usage(
                  values: {"region" => "us"},
                  presentation_breakdowns: [
                    {"presentation_by" => {"provider" => "aws"}, "units" => "1.0"}
                  ]
                )
              ]
            )
          ]
        )
      end

      it "diffs filter presentation_breakdowns by presentation_by" do
        result = diff_service.call
        expect(result).to be_success

        diff_filter = result.usage_diff.fetch("charges_usage").first.fetch("filters").first
        expect(diff_filter.fetch("presentation_breakdowns")).to eq(
          [
            {"presentation_by" => {"provider" => "aws"}, "units" => "0.1"},
            {"presentation_by" => {"provider" => "gcp"}, "units" => "0.4"}
          ]
        )
      end
    end

    context "when filters in grouped_usage contain presentation_breakdowns" do
      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              grouped_usage: [
                grouped_usage(
                  grouped_by: {"country" => "us"},
                  filters: [
                    filter_usage(
                      values: {"region" => "east"},
                      presentation_breakdowns: [
                        {"presentation_by" => {"provider" => "aws"}, "units" => "0.5"},
                        {"presentation_by" => {"provider" => "gcp"}, "units" => "0.2"}
                      ]
                    )
                  ],
                  presentation_breakdowns: []
                )
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              grouped_usage: [
                grouped_usage(
                  grouped_by: {"country" => "us"},
                  filters: [
                    filter_usage(
                      values: {"region" => "east"},
                      presentation_breakdowns: [
                        {"presentation_by" => {"provider" => "aws"}, "units" => "0.3"}
                      ]
                    )
                  ],
                  presentation_breakdowns: []
                )
              ]
            )
          ]
        )
      end

      it "diffs grouped_usage filter presentation_breakdowns by presentation_by" do
        result = diff_service.call
        expect(result).to be_success

        grouped = result.usage_diff.fetch("charges_usage").first.fetch("grouped_usage").first
        diff_filter = grouped.fetch("filters").first
        expect(diff_filter.fetch("presentation_breakdowns")).to eq(
          [
            {"presentation_by" => {"provider" => "aws"}, "units" => "0.2"},
            {"presentation_by" => {"provider" => "gcp"}, "units" => "0.2"}
          ]
        )
      end
    end

    context "when previous_daily_usage is nil" do
      let(:previous_daily_usage) { nil }

      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.5"}
              ]
            )
          ]
        )
      end

      let(:previous_usage) { nil }

      it "returns the current usage as diff (including presentation_breakdowns)" do
        expect(diff_service.call.usage_diff).to eq(usage)
      end
    end

    context "when previous_daily_usage is not provided" do
      subject(:diff_service) { described_class.new(daily_usage:) }

      let(:subscription) { create(:subscription) }
      let(:from_datetime) { Time.zone.parse("2022-07-01T00:00:00Z") }
      let(:to_datetime) { Time.zone.parse("2022-07-31T23:59:59Z") }

      let(:daily_usage) do
        build(
          :daily_usage,
          subscription:,
          from_datetime:,
          to_datetime:,
          usage_date: Date.new(2022, 7, 15),
          usage:
        )
      end

      let(:usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.5"}
              ]
            )
          ]
        )
      end

      let(:previous_usage) do
        usage_payload(
          charges_usage: [
            charge_usage(
              lago_id: "charge-a",
              presentation_breakdowns: [
                {"presentation_by" => {"region" => "us"}, "units" => "1.0"}
              ]
            )
          ]
        )
      end

      before do
        create(
          :daily_usage,
          subscription:,
          from_datetime:,
          to_datetime:,
          usage_date: Date.new(2022, 7, 14),
          usage: previous_usage
        )
      end

      it "automatically finds the previous usage and diffs presentation_breakdowns" do
        diff = diff_service.call.usage_diff
        expect(diff.fetch("charges_usage").first.fetch("presentation_breakdowns")).to eq(
          [{"presentation_by" => {"region" => "us"}, "units" => "0.5"}]
        )
      end
    end
  end

  describe "filters edited between snapshots" do
    def usage_values(amount_cents, units, events_count)
      {"amount_cents" => amount_cents, "units" => units, "events_count" => events_count}
    end

    def filter_usage(values, amount_cents, units, events_count, presentation_breakdowns: [])
      {
        "values" => values,
        "invoice_display_name" => nil,
        "presentation_breakdowns" => presentation_breakdowns,
        **usage_values(amount_cents, units, events_count)
      }
    end

    def usage_payload(filters, amount_cents, units, events_count)
      {
        "amount_cents" => amount_cents,
        "taxes_amount_cents" => 0,
        "charges_usage" => [
          {
            "charge" => {"lago_id" => "charge-a"},
            "filters" => filters,
            "grouped_usage" => [],
            "presentation_breakdowns" => [],
            **usage_values(amount_cents, units, events_count)
          }
        ]
      }
    end

    let(:diff_charge) { diff_service.call.usage_diff.fetch("charges_usage").first }
    let(:diff_filters) { diff_charge.fetch("filters").map { |f| f.slice("values", "amount_cents", "units", "events_count") } }

    context "when filter values are edited without new usage" do
      let(:previous_usage) do
        usage_payload([filter_usage({"model" => %w[a b]}, 1000, "10.0", 10)], 1000, "10.0", 10)
      end

      let(:usage) do
        usage_payload([filter_usage({"model" => %w[b]}, 1000, "10.0", 10)], 1000, "10.0", 10)
      end

      it "does not count the period-to-date usage of the edited filter as a new diff" do
        expect(diff_charge.slice("amount_cents", "units", "events_count")).to eq(usage_values(0, "0.0", 0))
        expect(diff_filters).to eq([{"values" => {"model" => %w[b]}, **usage_values(0, "0.0", 0)}])
      end
    end

    context "when a filter value is moved into a new filter and usage is received" do
      let(:previous_usage) do
        usage_payload([filter_usage({"model" => %w[a b]}, 1000, "10.0", 10)], 1000, "10.0", 10)
      end

      let(:usage) do
        usage_payload(
          [
            filter_usage({"model" => %w[b]}, 700, "7.0", 7),
            filter_usage({"model" => %w[a]}, 400, "4.0", 4)
          ],
          1100, "11.0", 11
        )
      end

      it "allocates the dropped filter usage so that filter diffs add up to the charge diff" do
        expect(diff_charge.slice("amount_cents", "units", "events_count")).to eq(usage_values(100, "1.0", 1))
        expect(diff_filters.map { |f| f["amount_cents"] }).to eq([64, 36])
        expect(diff_filters.sum { |f| f["events_count"] }).to eq(1)
        expect(diff_filters.sum { |f| BigDecimal(f["units"]) }).to eq(BigDecimal("1.0"))
      end
    end

    context "when a filter is removed and its usage falls back into the default bucket" do
      let(:previous_usage) do
        usage_payload(
          [
            filter_usage({"model" => %w[a]}, 300, "3.0", 3),
            filter_usage(nil, 700, "7.0", 7)
          ],
          1000, "10.0", 10
        )
      end

      let(:usage) do
        usage_payload([filter_usage(nil, 1050, "10.5", 11)], 1050, "10.5", 11)
      end

      it "deducts the removed filter usage from the remaining filters" do
        expect(diff_filters).to eq([{"values" => nil, **usage_values(50, "0.5", 1)}])
      end
    end

    context "when a filter is removed and its usage falls back into the default bucket next to an untouched filter" do
      let(:previous_usage) do
        usage_payload(
          [
            filter_usage({"model" => %w[a]}, 100, "1.0", 1),
            filter_usage({"model" => %w[b]}, 100, "1.0", 1),
            filter_usage(nil, 100, "1.0", 1)
          ],
          300, "3.0", 3
        )
      end

      let(:usage) do
        usage_payload(
          [
            filter_usage({"model" => %w[b]}, 100, "1.0", 1),
            filter_usage(nil, 200, "2.0", 2)
          ],
          300, "3.0", 3
        )
      end

      it "deducts the removed filter usage from the bucket that received it only" do
        expect(diff_filters).to eq(
          [
            {"values" => {"model" => %w[b]}, **usage_values(0, "0.0", 0)},
            {"values" => nil, **usage_values(0, "0.0", 0)}
          ]
        )
      end
    end

    context "when a filter is removed while an unrelated filter receives new usage" do
      let(:previous_usage) do
        usage_payload(
          [
            filter_usage({"model" => %w[a]}, 100, "1.0", 1),
            filter_usage({"model" => %w[b]}, 100, "1.0", 1),
            filter_usage(nil, 100, "1.0", 1)
          ],
          300, "3.0", 3
        )
      end

      let(:usage) do
        usage_payload(
          [
            filter_usage({"model" => %w[b]}, 150, "1.5", 2),
            filter_usage(nil, 200, "2.0", 2)
          ],
          350, "3.5", 4
        )
      end

      it "keeps the unrelated filter's own diff" do
        expect(diff_filters).to eq(
          [
            {"values" => {"model" => %w[b]}, **usage_values(50, "0.5", 1)},
            {"values" => nil, **usage_values(0, "0.0", 0)}
          ]
        )
      end
    end

    context "when a filter is replaced while an unrelated filter is added" do
      let(:previous_usage) do
        usage_payload([filter_usage({"model" => %w[a b]}, 1000, "10.0", 10)], 1000, "10.0", 10)
      end

      let(:usage) do
        usage_payload(
          [
            filter_usage({"model" => %w[a b]}, 1000, "10.0", 10).merge("values" => {"model" => %w[a b c]}),
            filter_usage({"region" => %w[eu], "model" => %w[d]}, 100, "1.0", 1)
          ],
          1100, "11.0", 11
        )
      end

      it "deducts the dropped filter from the filter overlapping it only" do
        expect(diff_filters).to eq(
          [
            {"values" => {"model" => %w[a b c]}, **usage_values(0, "0.0", 0)},
            {"values" => {"region" => %w[eu], "model" => %w[d]}, **usage_values(100, "1.0", 1)}
          ]
        )
      end
    end

    context "when a filter is replaced by fully specified filters and a more specific one" do
      let(:previous_usage) do
        usage_payload(
          [
            filter_usage({"model" => %w[a b]}, 1000, "10.0", 10),
            filter_usage(nil, 50, "1.0", 1)
          ],
          1050, "11.0", 11
        )
      end

      # Every a or b event is billed by a configured filter, so the default bucket only keeps its own gain
      let(:usage) do
        usage_payload(
          [
            filter_usage({"model" => %w[a]}, 600, "6.0", 6),
            filter_usage({"model" => %w[b]}, 300, "3.0", 3),
            filter_usage({"model" => %w[a], "region" => %w[eu]}, 100, "1.0", 1),
            filter_usage(nil, 70, "1.4", 2)
          ],
          1070, "11.4", 12
        )
      end

      it "does not deduct the dropped filter from the default bucket" do
        expect(diff_filters).to eq(
          [
            {"values" => {"model" => %w[a]}, **usage_values(0, "0.0", 0)},
            {"values" => {"model" => %w[b]}, **usage_values(0, "0.0", 0)},
            {"values" => {"model" => %w[a], "region" => %w[eu]}, **usage_values(0, "0.0", 0)},
            {"values" => nil, **usage_values(20, "0.4", 1)}
          ]
        )
      end
    end

    context "when a dropped filter's values are matched by a filter with more keys only" do
      let(:previous_usage) do
        usage_payload(
          [
            filter_usage({"model" => %w[a]}, 100, "1.0", 1),
            filter_usage(nil, 50, "1.0", 1)
          ],
          150, "2.0", 2
        )
      end

      # Events of model a outside eu fall back to the default bucket
      let(:usage) do
        usage_payload(
          [
            filter_usage({"model" => %w[a], "region" => %w[eu]}, 40, "0.4", 1),
            filter_usage(nil, 110, "1.6", 1)
          ],
          150, "2.0", 2
        )
      end

      it "keeps the default bucket as a receiver" do
        expect(diff_filters.sum { |f| f["amount_cents"] }).to eq(0)
        expect(diff_filters.map { |f| f["amount_cents"] }).to eq([0, 0])
      end
    end

    context "when a filter allowing all values is replaced" do
      let(:previous_usage) do
        usage_payload([filter_usage({"model" => %w[__ALL_FILTER_VALUES__]}, 1000, "10.0", 10)], 1000, "10.0", 10)
      end

      let(:usage) do
        usage_payload([filter_usage({"model" => %w[a]}, 1000, "10.0", 10)], 1000, "10.0", 10)
      end

      it "treats it as overlapping every value" do
        expect(diff_filters).to eq([{"values" => {"model" => %w[a]}, **usage_values(0, "0.0", 0)}])
      end
    end

    context "when existing usage is split into new filters with different prices" do
      let(:previous_usage) do
        usage_payload([filter_usage({"model" => %w[a b]}, 200, "2.0", 2)], 200, "2.0", 2)
      end

      let(:usage) do
        usage_payload(
          [
            filter_usage({"model" => %w[a]}, 100, "1.0", 1),
            filter_usage({"model" => %w[b]}, 1000, "1.0", 1)
          ],
          1100, "2.0", 2
        )
      end

      it "allocates units and events on their own weights and the amount at the dropped filter's price" do
        expect(diff_filters).to eq(
          [
            {"values" => {"model" => %w[a]}, **usage_values(0, "0.0", 0)},
            {"values" => {"model" => %w[b]}, **usage_values(900, "0.0", 0)}
          ]
        )
      end
    end

    context "when the edited filter has presentation breakdowns" do
      let(:previous_usage) do
        usage_payload(
          [
            filter_usage(
              {"model" => %w[a b]}, 1000, "10.0", 10,
              presentation_breakdowns: [{"presentation_by" => {"provider" => "aws"}, "units" => "10.0"}]
            )
          ],
          1000, "10.0", 10
        )
      end

      let(:usage) do
        usage_payload(
          [
            filter_usage(
              {"model" => %w[b]}, 1100, "11.0", 11,
              presentation_breakdowns: [
                {"presentation_by" => {"provider" => "aws"}, "units" => "10.0"},
                {"presentation_by" => {"provider" => "gcp"}, "units" => "1.0"}
              ]
            )
          ],
          1100, "11.0", 11
        )
      end

      it "deducts the dropped breakdowns from the new filter breakdowns" do
        filter = diff_charge.fetch("filters").sole
        expect(filter["units"]).to eq("1.0")
        expect(filter["presentation_breakdowns"]).to eq(
          [
            {"presentation_by" => {"provider" => "aws"}, "units" => "0.0"},
            {"presentation_by" => {"provider" => "gcp"}, "units" => "1.0"}
          ]
        )
      end
    end

    context "when a dropped presentation breakdown has no units" do
      let(:previous_usage) do
        usage_payload(
          [
            filter_usage(
              {"model" => %w[a b]}, 1000, "10.0", 10,
              presentation_breakdowns: [{"presentation_by" => {"provider" => "aws"}, "units" => nil}]
            )
          ],
          1000, "10.0", 10
        )
      end

      let(:usage) do
        usage_payload(
          [
            filter_usage(
              {"model" => %w[b]}, 1000, "10.0", 10,
              presentation_breakdowns: [{"presentation_by" => {"provider" => "aws"}, "units" => "10.0"}]
            )
          ],
          1000, "10.0", 10
        )
      end

      it "treats it as zero" do
        filter = diff_charge.fetch("filters").sole
        expect(filter.slice("amount_cents", "units", "events_count")).to eq(usage_values(0, "0.0", 0))
        expect(filter["presentation_breakdowns"]).to eq([{"presentation_by" => {"provider" => "aws"}, "units" => "10.0"}])
      end
    end

    context "when all filters are removed from the charge" do
      let(:previous_usage) do
        usage_payload([filter_usage({"model" => %w[a b]}, 1000, "10.0", 10)], 1000, "10.0", 10)
      end

      let(:usage) { usage_payload([], 1100, "11.0", 11) }

      it "keeps the charge diff and no filter" do
        expect(diff_charge.slice("amount_cents", "units", "events_count")).to eq(usage_values(100, "1.0", 1))
        expect(diff_filters).to eq([])
      end
    end

    context "when a single cent and event are split across receivers with half shares and a zero share" do
      let(:previous_usage) do
        usage_payload([filter_usage({"model" => %w[a b c]}, 1, "1.0", 1)], 1, "1.0", 1)
      end

      # The dropped filter's unit and event go to a and b in halves (equal gains), none to c
      let(:usage) do
        usage_payload(
          [
            filter_usage({"model" => %w[a]}, 1, "1.0", 1),
            filter_usage({"model" => %w[b]}, 1, "1.0", 1),
            filter_usage({"model" => %w[c]}, 0, "0.0", 0)
          ],
          2, "2.0", 2
        )
      end

      it "never deducts more than the total nor gives anything to the receiver without share" do
        expect(diff_filters.sum { |f| f["amount_cents"] }).to eq(1)
        expect(diff_filters.sum { |f| f["events_count"] }).to eq(1)
        expect(diff_filters.map { |f| f["amount_cents"] }).to all(be >= 0)
        expect(diff_filters.map { |f| f["events_count"] }).to all(be >= 0)
        expect(diff_filters.last).to eq({"values" => {"model" => %w[c]}, **usage_values(0, "0.0", 0)})
      end
    end

    context "when units are split across receivers in thirds" do
      let(:previous_usage) do
        usage_payload([filter_usage({"model" => %w[a b c]}, 0, "1.0", 0)], 0, "1.0", 0)
      end

      let(:usage) do
        usage_payload(
          [
            filter_usage({"model" => %w[a]}, 0, "1.0", 0),
            filter_usage({"model" => %w[b]}, 0, "1.0", 0),
            filter_usage({"model" => %w[c]}, 0, "1.0", 0)
          ],
          0, "3.0", 0
        )
      end

      it "keeps the units exact and non-negative" do
        units = diff_filters.map { |f| BigDecimal(f["units"]) }
        expect(units.sum).to eq(BigDecimal("2.0"))
        expect(units).to all(be >= 0)
      end
    end

    context "when filters nested in grouped usage are edited" do
      let(:previous_usage) do
        payload = usage_payload([], 1000, "10.0", 10)
        payload["charges_usage"].first["grouped_usage"] = [
          {
            "grouped_by" => {"region" => "eu"},
            "filters" => [filter_usage({"model" => %w[a b]}, 1000, "10.0", 10)],
            "presentation_breakdowns" => [],
            **usage_values(1000, "10.0", 10)
          }
        ]
        payload
      end

      let(:usage) do
        payload = usage_payload([], 1020, "10.2", 12)
        payload["charges_usage"].first["grouped_usage"] = [
          {
            "grouped_by" => {"region" => "eu"},
            "filters" => [filter_usage({"model" => %w[b]}, 1020, "10.2", 12)],
            "presentation_breakdowns" => [],
            **usage_values(1020, "10.2", 12)
          }
        ]
        payload
      end

      it "reconciles the grouped filters with the grouped diff" do
        grouped_filter = diff_charge.fetch("grouped_usage").first.fetch("filters").first
        expect(grouped_filter.slice("amount_cents", "units", "events_count")).to eq(usage_values(20, "0.2", 2))
      end
    end
  end
end
