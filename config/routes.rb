# frozen_string_literal: true
get 'admin/ai_enhancement', to: 'ai_settings#edit', as: :ai_settings
post 'admin/ai_enhancement', to: 'ai_settings#update'
post 'admin/ai_enhancement/refresh_models', to: 'ai_settings#refresh_models', as: :refresh_ai_models
post 'admin/ai_enhancement/reload_sources', to: 'ai_settings#reload_sources', as: :reload_ai_sources
post 'issues/:issue_id/ai_enhancements', to: 'ai_enhancements#create', as: :issue_ai_enhancements
get 'issues/:issue_id/ai_enhancements/:id', to: 'ai_enhancements#show', as: :issue_ai_enhancement
post 'issues/:issue_id/ai_enhancements/:id/reply', to: 'ai_enhancements#reply', as: :reply_issue_ai_enhancement
post 'issues/:issue_id/ai_enhancements/:id/apply', to: 'ai_enhancements#apply', as: :apply_issue_ai_enhancement
