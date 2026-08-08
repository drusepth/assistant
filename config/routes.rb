Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  get "setup" => "first_run#new", as: :setup
  post "setup" => "first_run#create"

  resources :invitations, only: %i[ create destroy ]
  get "join/:token" => "invitations#show", as: :join
  post "join/:token" => "invitations#accept"

  resources :household_members, only: %i[ update destroy ]
  resource :household, only: %i[ update ]

  get "welcome(/:step)" => "onboarding#show", as: :onboarding, constraints: { step: /[1-4]/ }
  patch "welcome/:step" => "onboarding#update", constraints: { step: /[1-4]/ }

  root "dashboard#show"
  get "today" => "today#show", as: :today
  get "calendar(/:year/:month)" => "calendar#show", as: :calendar,
    constraints: { year: /\d{4}/, month: /\d{1,2}/ }
  get "sections/:slug" => "sections#show", as: :section
  resources :hobbies, only: %i[ create destroy ]
  resources :groups, only: %i[ create destroy ]

  get "health/care-settings" => "care_settings#show", as: :care_settings
  patch "health/care-settings" => "care_settings#update"
  delete "health/care-settings/:kind_key" => "care_settings#destroy", as: :care_setting
  post "health/medications" => "medications#create", as: :medications

  post "career/win" => "career#create_win", as: :career_win
  post "career/comp_change" => "career#create_comp_change", as: :career_comp_change
  resources :job_feeds, only: %i[ create destroy ]

  resource :settings, only: %i[ show update ]
  resource :export, only: %i[ create ]
  resources :notification_channels, only: %i[ create destroy ]
  resource :model_profile, only: %i[ update ]
  resources :access_grants, only: %i[ create destroy ]
  resources :linked_accounts, only: %i[ create update destroy ] do
    member do
      post :sync
    end
  end

  namespace :events do
    resource :import, only: %i[ new create ]
  end
  resources :events
  resources :tasks do
    # The task page's embedded chat (D30) — find-or-create the bound run,
    # append the turn.
    resource :conversation, only: :create, module: :tasks
    member do
      patch :complete
      patch :reopen
      patch :reschedule
      patch :move
    end
  end
  resources :documents do
    member do
      post :analyze
      patch :apply_suggestion
    end
  end
  namespace :people do
    resource :import, only: %i[ new create ]
    resource :circle, only: %i[ create destroy ]
  end
  resources :people do
    member do
      patch :log_contact
    end
  end
  resources :goals do
    member do
      patch :complete
      patch :reopen
      post :break_down
    end
  end
  resources :notes

  resources :photos, except: :new do
    member do
      post :ingest
      post :caption
      patch :apply_suggestion
    end
  end
  resources :albums do
    member do
      post :add_photos
      delete :remove_photos
    end
  end
  resources :photo_people, only: %i[ create destroy ]

  resources :suggestions, only: [] do
    member do
      patch :accept
      patch :dismiss
      patch :snooze
    end
  end

  get "tools/:tool_slug/run" => "tool_runs#new", as: :new_tool_run
  post "tools/:tool_slug/run" => "tool_runs#create", as: :run_tool
  resources :tool_runs, only: %i[ show destroy ] do
    resources :messages, only: :create, controller: "tool_run_messages"
    resource :application_email, only: :create
    member do
      post :recap
      post :retry_reply
    end
  end

  namespace :admin do
    root "overview#show"
    post "datasets/refresh" => "datasets#refresh", as: :refresh_datasets
    post "datasets/import" => "datasets#import", as: :import_datasets
    resources :errors, only: :index do
      collection { delete :destroy_all }
    end
    resources :failed_jobs, only: [] do
      member do
        post :retry
        delete :discard
      end
      collection { delete :discard_all }
    end
    resource :reset, only: :create
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
