# frozen_string_literal: true
namespace :redmine_ai do
  desc 'Mark abandoned sessions older than 10 minutes failed; ensure their workers are stopped first'
  task expire_stuck: :environment do
    AiEnhancement.where(state: %w[queued processing]).where('updated_at < ?', 10.minutes.ago).find_each do |record|
      record.with_lock do
        next unless %w[queued processing].include?(record.state) && record.updated_at < 10.minutes.ago
        document = record.data
        document['error'] = 'Background processing expired. Start a new enhancement.'
        record.data = document
        record.state = 'failed'
        record.save!
      end
    end
  end

  desc 'Delete completed/non-running enhancement sessions older than 30 days; keep issue journals'
  task purge: :environment do
    AiEnhancement.where.not(state: %w[queued processing applying]).where('updated_at < ?', 30.days.ago).delete_all
  end
end
