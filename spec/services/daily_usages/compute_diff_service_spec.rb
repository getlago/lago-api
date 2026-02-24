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
