Rails.application.routes.draw do
  # Devise routes for authentication (registration disabled - admins create users)
  devise_for :users, skip: [:registrations]

  # Root route
  root "home#index"

  # Admin namespace (system admins only)
  namespace :admin do
    resources :users do
      member do
        post :impersonate
        post :add_membership
        delete :remove_membership
        patch :update_membership
      end
    end
  end

  # Stop impersonation route (available to anyone being impersonated)
  delete :stop_impersonation, to: 'admin/impersonations#destroy'

  # Authenticated routes
  authenticate :user do
    resources :shops do
      member do
        post :test_olx_connection
        post :setup_olx_data
        post :sync_from_olx
      end

      resources :products do
        collection do
          post :bulk_update_margin
          delete :bulk_destroy
          post :bulk_publish_to_olx
          post :bulk_update_on_olx
          delete :bulk_remove_from_olx
          delete :bulk_disconnect_from_olx
        end
        member do
          post :publish_to_olx
          post :publish_to_olx_live
          post :update_on_olx
          post :unpublish_from_olx
          delete :remove_from_olx
          delete :disconnect_from_olx
        end
      end
      resources :imports, only: [:index, :new, :create, :show] do
        member do
          post :start_processing
          post :retry_import
          get :preview
          get :progress
        end
      end
      resources :olx_category_templates do
        collection do
          get :load_attributes
          get :load_specs
          get :load_placeholders
        end
      end
    end
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA files
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
end
