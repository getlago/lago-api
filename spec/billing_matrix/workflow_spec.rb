# frozen_string_literal: true

require "rspec"
require "fileutils"
require "open3"
require "tmpdir"
require_relative "../../billing_matrix/ledger"

RSpec.describe "Billing matrix workflow persistence" do # rubocop:disable RSpec/DescribeClass
  let(:directory) { Dir.mktmpdir("matrix-workflow") }
  let(:checkout) { File.join(directory, "checkout") }
  let(:origin) { File.join(directory, "origin.git") }
  let(:output_path) { File.join(directory, "outputs") }
  let(:workflow) { YAML.safe_load_file(File.expand_path("../../.github/workflows/billing-matrix-daily.yml", __dir__)) }
  let(:steps) { workflow.fetch("jobs").fetch("billing-matrix").fetch("steps") }

  before do
    FileUtils.mkdir_p([File.join(checkout, "billing_matrix"), File.join(checkout, "tmp/billing_matrix"), File.join(directory, "bin")])
    FileUtils.cp(File.expand_path("../../billing_matrix/ledger.rb", __dir__), File.join(checkout, "billing_matrix/ledger.rb"))
    File.write(File.join(checkout, "billing_matrix/ledger.yml"), "[]\n")
    File.write(File.join(directory, "bin/gh"), "#!/bin/sh\nprintf '%s\\n' \"$OPEN_LEDGER_PR\"\n")
    FileUtils.chmod(0o755, File.join(directory, "bin/gh"))
    write_results("passed")
    command("ruby", "billing_matrix/ledger.rb", "--apply")
    command("git", "init", "--bare", origin)
    git("init", "--initial-branch=main")
    git("config", "user.name", "Workflow test")
    git("config", "user.email", "workflow@example.test")
    git("add", "billing_matrix")
    git("commit", "-m", "test: initialize ledger fixture")
    git("remote", "add", "origin", origin)
    git("push", "origin", "main")
  end

  after { FileUtils.remove_entry(directory) }

  def command(*arguments, env: {})
    isolated_env = {"GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_NOSYSTEM" => "1"}
    stdout, stderr, status = Open3.capture3(isolated_env.merge(env), *arguments, chdir: checkout)
    expect(status).to be_success, "#{arguments.inspect}\n#{stdout}\n#{stderr}"
    stdout.strip
  end

  def git(*arguments)
    command("git", *arguments)
  end

  def write_results(verdict)
    results = {"run" => {"summary" => {"canaries_total" => 1, "canaries_unproven" => 0}},
               "rows" => [{"id" => "smoke/example", "area" => "smoke", "verdict" => verdict}]}
    File.write(File.join(checkout, "tmp/billing_matrix/results.json"), JSON.generate(results))
  end

  def step(id, env)
    File.write(output_path, "")
    script = steps.find { it["id"] == id }.fetch("run")
    command("bash", "-e", "-o", "pipefail", "-c", script, env: env.merge("GITHUB_OUTPUT" => output_path))
    File.read(output_path)
  end

  def run_workflow(verdict, open_pr: "1", dry_run: false)
    git("checkout", "--detach", "--force", "main")
    write_results(verdict)
    env = {"PATH" => "#{directory}/bin:#{ENV.fetch("PATH")}", "GH_REPO" => "example/billing",
           "OPEN_LEDGER_PR" => open_pr, "RUN_COMPLETE" => "true"}
    state = step("ledger_state", env)
    report = step("ledger", env)
    pushed = if dry_run
      ""
    else
      step("commit", env.merge("LEDGER_HEAD" => state[/^head=(.*)$/, 1]))
    end
    [report, pushed]
  end

  def remote_head
    git("ls-remote", "origin", "refs/heads/billing-matrix/ledger").split.first
  end

  it "reports each transition once across fresh checkouts while the ledger PR remains open" do
    report, pushed = run_workflow("failed")
    expect(report).to include("has_news=true", "1 newly failing")
    expect(pushed).to include("pushed=true")
    failed_head = remote_head

    report, pushed = run_workflow("failed")
    expect(report).to include("has_news=false")
    expect(pushed).to include("pushed=false")
    expect(remote_head).to eq(failed_head)

    report, pushed = run_workflow("passed")
    expect(report).to include("has_news=true", "1 fixed")
    expect(pushed).to include("pushed=true")

    report, pushed = run_workflow("passed")
    expect(report).to include("has_news=false")
    expect(pushed).to include("pushed=true")
    expect(pushed).to include("has_changes=false")
    expect(steps.find { it["name"] == "Open PR if needed" }.fetch("if")).to include("steps.commit.outputs.has_changes == 'true'")
    expect(remote_head).to eq(git("rev-parse", "main"))
    expect(YAML.safe_load(git("show", "#{remote_head}:billing_matrix/ledger.yml"))).to eq([])
  end

  it "ignores a stale remote ledger branch whose PR was closed or merged" do
    run_workflow("failed")
    report, pushed = run_workflow("failed", open_pr: "")

    expect(report).to include("has_news=true", "1 newly failing")
    expect(pushed).to include("pushed=true")
  end

  it "reads pending state during a dry run without publishing it" do
    run_workflow("failed")
    old_head = remote_head

    report, = run_workflow("passed", dry_run: true)

    expect(report).to include("has_news=true", "1 fixed")
    expect(remote_head).to eq(old_head)
    expect(steps.find { it["id"] == "commit" }.fetch("if")).to include("env.DRY_RUN != 'true'")
    report, pushed = run_workflow("failed")
    expect(report).to include("has_news=false")
    expect(pushed).to include("pushed=false")
  end
end
