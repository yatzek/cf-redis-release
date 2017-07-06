require 'yaml'
require 'bosh/template/renderer'
require 'bosh/template/property_helper'

class BoshEmulator
  extend ::Bosh::Template::PropertyHelper

  def self.director_merge(manifest, job_name)
    manifest_job_properties = manifest['instance_groups'][0]['jobs'][0].fetch('properties', {})

    job_spec = YAML.load_file("jobs/#{job_name}/spec")
    spec_properties = job_spec["properties"]

    effective_properties = {}
    spec_properties.each_pair do |name, definition|
      copy_property(effective_properties, manifest_job_properties, name, definition["default"])
    end

    manifest.merge({"properties" => effective_properties})
  end
end

RSpec.describe 'smoke-tests config.json' do
  let(:renderer) do
    context = BoshEmulator.director_merge(YAML.load_file(manifest_file), 'smoke-tests')
    context['links'] = {
      'redis_broker' => {
        'instances' => [
          {
            'address' => 'redis-broker-address'
          }
        ],
        'properties' => {}
      }
    }

    Bosh::Template::Renderer.new(context: context.to_json)
  end

  let(:rendered_template) { renderer.render('jobs/smoke-tests/templates/config.json.erb') }

  context 'when all properties are configured' do
    let(:manifest_file) { 'spec/unit/fixtures/smoke_tests.yml' }

    it 'templates all the configured properties' do
      expected_config = {
        "api" => "a-cf-url",
        "apps_domain" => "an-apps-domain",
        "system_domain" => "a-system-domain",
        "admin_user" => "a-username",
        "admin_password" => "a-password",
        "service_name" => "a-service-name",
        "space_name" => "redis-smoke-test-space",
        "org_name" => "redis-smoke-test-org",
        "plan_names" => [
          "shared-vm",
          "dedicated-vm"
        ],
        "retry" => {
          "max_attempts" => 5,
          "backoff" => "linear",
          "baseline_interval_milliseconds" => 1000
        },
        "skip_ssl_validation" => false,
        "create_permissive_security_group" => false,
        "security_groups" => [
          {
            "protocol": "tcp",
            "ports": "6379",
            "destination": "a-dedicated-node-ip"
          },
          {
            "protocol": "tcp",
            "ports": "32768-61000",
            "destination": "redis-broker-address"
          }
        ]
      }

      expect(JSON.parse(rendered_template)).to(eq(expected_config))
    end
  end
end
