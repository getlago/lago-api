# frozen_string_literal: true

namespace :admin_staff do
  desc "Seed (or reset) Lago staff accounts in the admin_users table"
  task seed: :environment do
    reset = ENV["RESET"] == "true"
    raw = ENV["STAFF"].to_s

    entries =
      if raw.present?
        raw.split(",").map do |entry|
          email, role = entry.split(":", 2).map { |v| v.to_s.strip }
          [email, (role.presence || "cs")]
        end
      else
        default_entries
      end

    if entries.empty?
      puts "No staff entries found. Pass STAFF=\"email:role,email:role\" or set a default list."
      exit 1
    end

    puts "Seeding #{entries.size} admin_user(s). Reset existing passwords: #{reset}"
    puts "-" * 72

    entries.each do |email, role|
      next if email.blank?

      existing = AdminUser.find_by("LOWER(email) = ?", email.downcase)

      if existing && !reset
        existing.update!(role: role) unless existing.role == role
        puts format("%-35s %-6s (exists, password unchanged)", email, role)
        next
      end

      password = SecureRandom.alphanumeric(20)

      if existing
        existing.update!(password: password, role: role)
        label = "reset"
      else
        AdminUsers::CreateService.call!(email: email, password: password, role: role)
        label = "created"
      end

      puts format("%-35s %-6s (%s) password: %s", email, role, label, password)
    end

    puts "-" * 72
    puts "Save these passwords to 1Password. They will NOT be shown again."
    puts "Log in via the `adminLoginUser` GraphQL mutation."
  end

  desc "Revoke a staff account. Usage: rake admin_staff:revoke EMAIL=x@getlago.com"
  task revoke: :environment do
    email = ENV["EMAIL"].to_s.strip.downcase
    if email.blank?
      puts "EMAIL is required. Usage: rake admin_staff:revoke EMAIL=x@getlago.com"
      exit 1
    end

    admin = AdminUser.find_by("LOWER(email) = ?", email)
    if admin.nil?
      puts "No admin user with email #{email}"
      exit 0
    end

    admin.destroy!
    puts "Revoked admin user #{email}."
  end

  def default_entries
    [
      ["miguel@getlago.com", "admin"],
      ["at@getlago.com", "admin"],
      ["anh-tu@getlago.com", "admin"],
      ["brian@getlago.com", "admin"],
      ["raffi@getlago.com", "admin"],
      ["jeremy@getlago.com", "admin"],
      ["lovro@getlago.com", "cs"]
    ]
  end
end
