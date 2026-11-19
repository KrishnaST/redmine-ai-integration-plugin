# frozen_string_literal: true
get 'admin/ai_enhancement', to: 'ai_settings#edit', as: :ai_settings
post 'admin/ai_enhancement', to: 'ai_settings#update'
post 'issues/:issue_id/ai_enhancements', to: 'ai_enhancements#create', as: :issue_ai_enhancements
get 'issues/:issue_id/ai_enhancements/:id', to: 'ai_enhancements#show', as: :issue_ai_enhancement
post 'issues/:issue_id/ai_enhancements/:id/reply', to: 'ai_enhancements#reply', as: :reply_issue_ai_enhancement
post 'issues/:issue_id/ai_enhancements/:id/apply', to: 'ai_enhancements#apply', as: :apply_issue_ai_enhancement
