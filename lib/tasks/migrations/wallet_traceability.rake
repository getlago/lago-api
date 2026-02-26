# frozen_string_literal: true

require "csv"
require "parallel"

class WalletMigration
  def initialize(dry_run: true, limit: nil, batch_size: 1000, output_limit: 50,
    thread_count: 0, output_file: nil, scope: Wallet.where(traceable: false))
    @scope = scope
    @dry_run = dry_run
    @limit = limit
    @batch_size = batch_size
    @output_limit = output_limit
    @thread_count = thread_count
    @output_file = output_file
  end

  def run
    puts "Wallet migration — mode: #{@dry_run ? "DRY-RUN (validation only)" : "BACKFILL (writing data)"}"
    puts "Limit: #{@limit || "all"}, Batch size: #{@batch_size}, Threads: #{@thread_count.zero? ? "sequential" : @thread_count}"
    puts "=" * 60

    if @dry_run
      run_validation
    else
      run_backfill
    end
  end

  private

  attr_reader :scope

  # ---------------------------------------------------------------------------
  # Dry-run: validate without writing
  # ---------------------------------------------------------------------------

  def run_validation
    mutex = Mutex.new
    total_wallets = 0
    migratable_wallets = 0
    problematic_wallets = []
    wallet_count = scope.count

    iterate_customers_in_batches do |customer_ids|
      batch_wallet_count = 0

      Parallel.each(customer_ids, in_threads: @thread_count) do |customer_id|
        ActiveRecord::Base.connection_pool.with_connection do
          wallets = scope.where(customer_id: customer_id).includes(:customer, :organization, :wallet_transactions).to_a
          wallets.each do |wallet|
            issues = validate_wallet(wallet)
            mutex.synchronize do
              total_wallets += 1
              batch_wallet_count += 1
              if issues.empty?
                migratable_wallets += 1
              else
                problematic_wallets << {
                  wallet_id: wallet.id,
                  customer_id: wallet.customer_id,
                  customer_name: wallet.customer.name,
                  organization_id: wallet.organization_id,
                  organization_name: wallet.organization.name,
                  created_at: wallet.created_at,
                  issues: issues
                }
              end
            end
          end
        end
      end
      mutex.synchronize { print_progress("Validating", total_wallets, wallet_count) }
      batch_wallet_count
    end

    clear_progress
    print_validation_summary(total_wallets, migratable_wallets, problematic_wallets)
  end

  def settled_inbound(wallet)
    wallet.wallet_transactions.select { |tx| tx.inbound? && tx.settled? }.sort_by(&:created_at)
  end

  def settled_outbound(wallet)
    wallet.wallet_transactions.select { |tx| tx.outbound? && tx.settled? }.sort_by(&:created_at)
  end

  def validate_wallet(wallet)
    issues = []

    # Check wallet-level issues
    if wallet.balance_cents < 0
      issues << "Negative wallet balance: #{wallet.balance_cents} cents"
    end

    # Check transaction-level issues
    validate_transactions(wallet, issues)

    # Simulate FIFO consumption and check for issues
    simulation_result = simulate_fifo_consumption(wallet, issues)

    # Check balance drift
    drift = wallet.balance_cents - simulation_result[:final_balance]
    if drift != 0
      issues << if drift.abs < 100
        "Balance drift < 1 unit: #{drift} cents (wallet: #{wallet.balance_cents}, simulated: #{simulation_result[:final_balance]}) — likely rounding"
      else
        "Balance drift >= 1 unit: #{drift} cents (wallet: #{wallet.balance_cents}, simulated: #{simulation_result[:final_balance]})"
      end
    end

    issues
  end

  def validate_transactions(wallet, issues)
    settled_inbound(wallet).each do |tx|
      amount = tx.amount_cents
      if amount != amount.to_i
        issues << "Decimal amount_cents on inbound #{tx.id}: #{amount} (expected integer)"
      end
      if amount < 0
        issues << "Negative amount_cents on inbound #{tx.id}: #{amount}"
      end
    end

    settled_outbound(wallet).each do |tx|
      amount = tx.amount_cents
      if amount != amount.to_i
        issues << "Decimal amount_cents on outbound #{tx.id}: #{amount} (expected integer)"
      end
      if amount < 0
        issues << "Negative amount_cents on outbound #{tx.id}: #{amount}"
      end
    end
  end

  def simulate_fifo_consumption(wallet, issues)
    inbound_txs = settled_inbound(wallet)
    outbound_txs = settled_outbound(wallet)

    if outbound_txs.any? && inbound_txs.empty?
      issues << "No inbound transactions found but #{outbound_txs.size} outbound exist — missing transaction history"
      return {final_balance: 0}
    end

    # Pre-sort inbound by consumption priority (stable across all outbound)
    sorted_inbound = inbound_txs.map do |tx|
      {id: tx.id, remaining: tx.amount_cents, transaction_status: tx.transaction_status,
       priority: tx.priority || 0, created_at: tx.created_at}
    end.sort_by { |d| [(d[:transaction_status] == "granted") ? 0 : 1, d[:priority], d[:created_at]] }

    # Index for newly eligible inbound (sorted by created_at for eligibility check)
    inbound_by_time = inbound_txs.map do |tx|
      {id: tx.id, created_at: tx.created_at}
    end.sort_by { |d| d[:created_at] }
    time_cursor = 0
    eligible_ids = Set.new

    # Remaining balance lookup
    sorted_inbound.index_by { |d| d[:id] }

    outbound_txs.each do |outbound|
      amount_to_consume = outbound.amount_cents
      next if amount_to_consume <= 0

      # Advance eligibility cursor — inbound created_at <= outbound created_at
      while time_cursor < inbound_by_time.size && inbound_by_time[time_cursor][:created_at] <= outbound.created_at
        eligible_ids.add(inbound_by_time[time_cursor][:id])
        time_cursor += 1
      end

      available = sorted_inbound.select { |d| eligible_ids.include?(d[:id]) && d[:remaining] > 0 }

      if available.empty?
        issues << "Outbound #{outbound.id} (#{outbound.created_at.to_date}): no inbound transactions available — missing transaction history"
        next
      end

      total_available = available.sum { |d| d[:remaining] }

      available.each do |data|
        break if amount_to_consume <= 0

        consume_amount = [data[:remaining], amount_to_consume].min
        data[:remaining] -= consume_amount
        amount_to_consume -= consume_amount
      end

      if amount_to_consume > 0
        issues << "Outbound #{outbound.id} (#{outbound.created_at.to_date}): insufficient inbound to consume #{outbound.amount_cents} cents " \
                  "(available: #{total_available} cents, shortfall: #{amount_to_consume} cents)"
      end
    end

    final_balance = sorted_inbound.sum { |d| d[:remaining] }

    {final_balance: final_balance}
  end

  def print_validation_summary(total_wallets, migratable_wallets, problematic_wallets)
    puts "\n" + "=" * 60
    puts "Total wallets: #{total_wallets}"
    puts "Migratable: #{migratable_wallets}"
    puts "Problematic: #{problematic_wallets.size}"

    if problematic_wallets.any?
      puts "\n" + "=" * 60
      puts "PROBLEMATIC WALLETS (first #{@output_limit}):"
      problematic_wallets.first(@output_limit).each do |pw|
        puts "  Wallet #{pw[:wallet_id]}:"
        puts "    - Customer: #{pw[:customer_name]} (#{pw[:customer_id]})"
        puts "    - Org: #{pw[:organization_name]} (#{pw[:organization_id]})"
        puts "    - Created At: #{pw[:created_at].to_date}"
        puts "    - Issues:"
        pw[:issues].first(3).each { |issue| puts "      - #{issue}" }
        remaining = pw[:issues].size - 3
        puts "      - ... and #{remaining} more issues" if remaining > 0
      end
      hidden = problematic_wallets.size - @output_limit
      puts "  ... and #{hidden} more problematic wallets" if hidden > 0
    end

    puts "\n" + "=" * 60
    percentage = (total_wallets > 0) ? (migratable_wallets.to_f / total_wallets * 100).round(2) : 0
    puts "Migration readiness: #{percentage}%"

    if @output_file && problematic_wallets.any?
      export_csv(problematic_wallets, headers: %w[wallet_id customer_id customer_name organization_id organization_name created_at issues]) do |pw|
        [pw[:wallet_id], pw[:customer_id], pw[:customer_name], pw[:organization_id], pw[:organization_name], pw[:created_at].to_date, pw[:issues].join(" | ")]
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Backfill: write data
  # ---------------------------------------------------------------------------

  def run_backfill
    mutex = Mutex.new
    customers_processed = 0
    wallets_processed = 0
    errors = []
    wallet_count = scope.count

    iterate_customers_in_batches do |customer_ids|
      batch_wallet_count = 0

      Parallel.each(customer_ids, in_threads: @thread_count) do |customer_id|
        ActiveRecord::Base.connection_pool.with_connection do
          ApplicationRecord.transaction do
            ApplicationRecord.with_advisory_lock!("customer-#{customer_id}", timeout_seconds: 10, transaction: true) do
              wallets = scope.where(customer_id: customer_id).includes(wallet_transactions: :fundings).to_a
              next if wallets.empty?

              wallets.each { |wallet| backfill_wallet_transactions(wallet) }

              Wallet.where(id: wallets.map(&:id)).update_all(traceable: true) # rubocop:disable Rails/SkipsModelValidations

              mutex.synchronize do
                wallets_processed += wallets.size
                batch_wallet_count += wallets.size
                customers_processed += 1
              end
            rescue => e
              mutex.synchronize { errors << {customer_id: customer_id, error: e.message} }
              raise ActiveRecord::Rollback
            end
          end
        end
      end
      mutex.synchronize { print_progress("Backfilling", wallets_processed + errors.size, wallet_count) }
      batch_wallet_count
    end

    clear_progress
    print_backfill_summary(customers_processed, wallets_processed, errors)
  end

  def backfill_wallet_transactions(wallet)
    inbound_txs = settled_inbound(wallet)

    # Step 1: Initialize all settled inbound transactions with full amount
    inbound_txs.each do |tx|
      next if tx.remaining_amount_cents.present?
      tx.update_column(:remaining_amount_cents, tx.amount_cents) # rubocop:disable Rails/SkipsModelValidations
    end

    # Pre-sort inbound by consumption priority (stable across all outbound)
    sorted_inbound = inbound_txs.map do |tx|
      {id: tx.id, transaction: tx, remaining: tx.amount_cents, transaction_status: tx.transaction_status,
       priority: tx.priority || 0, created_at: tx.created_at}
    end.sort_by { |d| [(d[:transaction_status] == "granted") ? 0 : 1, d[:priority], d[:created_at]] }

    # Index for newly eligible inbound (sorted by created_at for eligibility check)
    inbound_by_time = inbound_txs.sort_by(&:created_at)
    time_cursor = 0
    eligible_ids = Set.new

    # Step 2: Process settled outbound transactions in chronological order
    settled_outbound(wallet).each do |outbound|
      next if outbound.fundings.any?

      amount_to_consume = outbound.amount_cents
      next if amount_to_consume <= 0

      # Advance eligibility cursor
      while time_cursor < inbound_by_time.size && inbound_by_time[time_cursor].created_at <= outbound.created_at
        eligible_ids.add(inbound_by_time[time_cursor].id)
        time_cursor += 1
      end

      consumption_records = []

      sorted_inbound.each do |data|
        break if amount_to_consume <= 0
        next unless eligible_ids.include?(data[:id]) && data[:remaining] > 0

        consume_amount = [data[:remaining], amount_to_consume].min

        consumption_records << {
          organization_id: wallet.organization_id,
          inbound_wallet_transaction_id: data[:id],
          outbound_wallet_transaction_id: outbound.id,
          consumed_amount_cents: consume_amount,
          created_at: outbound.created_at,
          updated_at: Time.current
        }

        data[:remaining] -= consume_amount
        amount_to_consume -= consume_amount
      end

      if amount_to_consume > 0
        raise "Wallet #{wallet.id}: Could not fully consume outbound #{outbound.id}, #{amount_to_consume} cents remaining"
      end

      WalletTransactionConsumption.insert_all!(consumption_records) if consumption_records.any? # rubocop:disable Rails/SkipsModelValidations
    end

    # Step 3: Update remaining_amount_cents based on final state
    sorted_inbound.each do |data|
      data[:transaction].update_column(:remaining_amount_cents, data[:remaining]) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def print_backfill_summary(customers_processed, wallets_processed, errors)
    puts "\n" + "=" * 60
    puts "Customers processed: #{customers_processed}"
    puts "Wallets processed: #{wallets_processed}"
    puts "Errors: #{errors.size}"

    if errors.any?
      puts "\nErrors (first 20):"
      errors.first(20).each do |e|
        puts "  Customer #{e[:customer_id]}: #{e[:error]}"
      end
    end

    if @output_file && errors.any?
      export_csv(errors, headers: %w[customer_id error]) do |e|
        [e[:customer_id], e[:error]]
      end
    end
  end

  # ---------------------------------------------------------------------------
  # CSV export
  # ---------------------------------------------------------------------------

  def export_csv(records, headers:)
    CSV.open(@output_file, "w") do |csv|
      csv << headers
      records.each { |record| csv << yield(record) }
    end
    puts "CSV exported to #{@output_file} (#{records.size} records)"
  end

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  # Iterates distinct customer IDs in batches using cursor-based pagination.
  # The block must return the number of wallets processed in that batch.
  # The limit is best-effort: we stop fetching new customer batches once the
  # cumulative wallet count reaches @limit, but all wallets for a customer
  # are always processed atomically.
  def iterate_customers_in_batches
    wallets_processed = 0
    last_customer_id = nil

    loop do
      break if @limit && wallets_processed >= @limit

      query = scope
      query = query.where(Wallet.arel_table[:customer_id].gt(last_customer_id)) if last_customer_id
      customer_ids = query.order(:customer_id).distinct.limit(@batch_size).pluck(:customer_id)
      break if customer_ids.empty?

      last_customer_id = customer_ids.last

      batch_wallet_count = yield(customer_ids)
      wallets_processed += batch_wallet_count
    end
  end

  def print_progress(label, current, total)
    return if total == 0

    percentage = (current.to_f / total * 100).round(1)
    bar_width = 30
    filled = (current.to_f / total * bar_width).round
    bar = "#" * filled + "-" * (bar_width - filled)
    print "\r#{label}: [#{bar}] #{current}/#{total} (#{percentage}%)"
  end

  def clear_progress
    print "\r" + " " * 80 + "\r"
  end
end

namespace :migrations do
  desc "Migrate wallets to traceable (dry_run=true by default)"
  task wallet_traceability: :environment do
    Rails.logger.level = :info

    dry_run = ENV.fetch("dry_run", "true") != "false"
    include_terminated = ENV["include_terminated"] == "true"
    scope = Wallet.where(traceable: false)
    scope = scope.active unless include_terminated
    scope = scope.where(organization_id: ENV["organization_id"]) if ENV["organization_id"].present?

    options = {scope:, dry_run:}
    options[:limit] = ENV["limit"].to_i if ENV["limit"].present?
    options[:batch_size] = ENV["batch_size"].to_i if ENV["batch_size"].present?
    options[:output_limit] = ENV["output_limit"].to_i if ENV["output_limit"].present?
    options[:thread_count] = ENV["thread_count"].to_i if ENV["thread_count"].present?
    options[:output_file] = ENV["output_file"] if ENV["output_file"].present?

    WalletMigration.new(**options).run
  end
end
