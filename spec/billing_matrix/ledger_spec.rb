# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../billing_matrix/ledger"

RSpec.describe BillingMatrix::Ledger do
  let(:directory) { Dir.mktmpdir("matrix-ledger") }
  let(:ledger_path) { File.join(directory, "ledger.yml") }

  before { File.write(ledger_path, "[]\n") }
  after { FileUtils.remove_entry(directory) }

  def run_ledger(verdict, canaries_total: 1, canaries_unproven: 0, pins: nil, format: "text")
    entries = YAML.safe_load_file(ledger_path, permitted_classes: [Date])
    results = {"run" => {"summary" => {"canaries_total" => canaries_total, "canaries_unproven" => canaries_unproven}},
               "rows" => [{"id" => "smoke/example", "area" => "smoke", "verdict" => verdict, "error" => "setup failed"}]}
    results["rows"].first["pins"] = pins unless pins.nil?
    ledger = described_class.new(results:, entries:, today: Date.new(2026, 9, 11))
    ledger.run(ledger: ledger_path, apply: true, format:)
  end

  it "reports failures and fixes once, then silently prunes a fixed entry" do
    expect { run_ledger("failed") }.to output(/newly failing \(1\)/).to_stdout
    expect { run_ledger("failed") }.to output("\n").to_stdout
    expect { run_ledger("passed") }.to output(/fixed \(1\)/).to_stdout
    expect { run_ledger("passed") }.to output("\n").to_stdout
    expect(YAML.safe_load_file(ledger_path)).to eq([])
  end

  it "reports pinned failures and fixes once with their finding IDs" do
    expect { run_ledger("failed", pins: %w[F69 BIL-537]) }.to output(/smoke\/example \(F69, BIL-537\)/).to_stdout
    expect(YAML.safe_load_file(ledger_path).first.fetch("pins")).to eq(%w[F69 BIL-537])
    expect { run_ledger("failed", pins: %w[F69 BIL-537]) }.to output("\n").to_stdout
    expect { run_ledger("passed", pins: %w[F69 BIL-537], format: "slack") }.to output(/1 fixed.*`smoke\/example` \(F69, BIL-537\)/m).to_stdout
    expect { run_ledger("passed", pins: %w[F69 BIL-537]) }.to output("\n").to_stdout
    expect(YAML.safe_load_file(ledger_path)).to eq([])
  end

  it "silently associates existing failures while preserving their history and notes" do
    original = {"id" => "smoke/example", "status" => "failed", "first_seen" => "2026-08-26", "note" => "Reviewed finding"}
    File.write(ledger_path, YAML.dump([original]))

    expect { run_ledger("failed", pins: ["F69"]) }.to output("\n").to_stdout
    expect(YAML.safe_load_file(ledger_path)).to eq([original.merge("pins" => ["F69"], "last_seen" => "2026-09-11")])
    expect { run_ledger("passed", format: "slack") }.to output(/`smoke\/example` \(F69\)/).to_stdout
    expect(YAML.safe_load_file(ledger_path).first.fetch("pins")).to eq(["F69"])
  end

  it "keeps transitions separate for rows pinning the same finding" do
    entries = [{"id" => "smoke/known", "pins" => ["F69"], "status" => "failed", "first_seen" => "2026-08-26"}]
    results = {"run" => {"summary" => {"canaries_total" => 1}},
               "rows" => %w[smoke/known smoke/new].map { {"id" => it, "area" => "smoke", "pins" => ["F69"], "verdict" => "failed"} }}
    ledger = described_class.new(results:, entries:, today: Date.new(2026, 9, 11))

    expect { ledger.run(ledger: ledger_path, apply: true, format: "slack") }.to output(/1 newly failing.*`smoke\/new` \(F69\).*1 still failing/m).to_stdout
    expect(YAML.safe_load_file(ledger_path).map { it.fetch("id") }).to eq(%w[smoke/known smoke/new])
  end

  it "reports a recurrence while preserving the original first-seen date" do
    original = [{"id" => "smoke/example", "status" => "fixed", "first_seen" => "2026-08-26", "fixed_on" => "2026-09-10", "pins" => ["F69"]}]
    File.write(ledger_path, YAML.dump(original))
    expect { run_ledger("failed") }.to output(/failing again \(1\).*smoke\/example \(F69\)/m).to_stdout
    expect(YAML.safe_load_file(ledger_path).first).to include("status" => "failed", "first_seen" => "2026-08-26")
  end

  it "reports scenario errors without marking known failures as fixed" do
    original = [{"id" => "smoke/example", "status" => "failed", "first_seen" => "2026-08-26", "pins" => ["F69"]}]
    File.write(ledger_path, YAML.dump(original))
    expect { run_ledger("errored", pins: ["BIL-537"]) }.to output(/errored \(1\).*setup failed/m).to_stdout
    expect(YAML.safe_load_file(ledger_path)).to eq(original)
  end

  it "refuses to update the ledger when a canary is unproven" do
    expect { expect(run_ledger("failed", canaries_unproven: 1)).to eq(2) }.to output(/refusing to apply/).to_stderr
    expect(File.read(ledger_path)).to eq("[]\n")
  end

  it "refuses to update the ledger without canaries" do
    expect { expect(run_ledger("failed", canaries_total: 0)).to eq(2) }.to output(/no canaries/).to_stderr
    expect(File.read(ledger_path)).to eq("[]\n")
  end
end
