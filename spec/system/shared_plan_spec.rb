require 'system_spec_helper'
require 'support/redis_service_client'
require 'system/shared_examples/redis_instance'

require 'prof/external_spec/shared_examples/service'
require 'prof/marketplace_service'

describe 'shared plan' do
  def service
    Prof::MarketplaceService.new(
      name: bosh_manifest.property('redis.broker.service_name'),
      plan: 'shared-vm'
    )
  end

  before(:all) do
    @service_broker_host = bosh_director.ips_for_job(
      environment.bosh_service_broker_job_name,
      bosh_manifest.deployment_name,
    ).first
  end

  # TODO do not manually run drain once bosh bug fixed
  let(:manually_drain) { '/var/vcap/jobs/cf-redis-broker/bin/drain' }

  describe 'redis provisioning' do
    before(:all) do
      @preprovision_timestamp = broker_ssh.execute('date +%s')
      @service_instance       = service_broker.provision_instance(service.name, service.plan)
    end

    after(:all) do
      service_broker.deprovision_instance(@service_instance)
    end

    it 'logs instance provisioning' do
      vm_log = broker_ssh.execute('sudo cat /var/log/syslog')
      contains_expected_log = drop_log_lines_before(@preprovision_timestamp, vm_log).any? do |line|
        line.include?('Successfully provisioned Redis instance') &&
        line.include?('shared-vm') &&
        line.include?(@service_instance.id)
      end

      expect(contains_expected_log).to be true
    end
  end

  describe 'redis deprovisioning' do
    before(:all) do
      @service_instance = service_broker.provision_instance(service.name, service.plan)

      @predeprovision_timestamp = broker_ssh.execute("date +%s")
      service_broker.deprovision_instance(@service_instance)
    end

    it 'logs instance deprovisioning' do
      vm_log = broker_ssh.execute('sudo cat /var/log/syslog')
      contains_expected_log = drop_log_lines_before(@predeprovision_timestamp, vm_log).any? do |line|
        line.include?('Successfully deprovisioned Redis instance') &&
        line.include?('shared-vm') &&
        line.include?(@service_instance.id)
      end

      expect(contains_expected_log).to be true
    end
  end

  context 'when recreating vms' do
    before(:all) do
      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @service_binding  = service_broker.bind_instance(@service_instance)

      @service_client = service_client_builder(@service_binding)
      @service_client.write('test_key', 'test_value')
      expect(@service_client.read('test_key')).to eq('test_value')

      bosh_director.stop(environment.bosh_service_broker_job_name, 0)
      bosh_director.recreate_all([environment.bosh_service_broker_job_name])
    end

    after(:all) do
      service_broker.unbind_instance(@service_binding)
      service_broker.deprovision_instance(@service_instance)
    end

    it 'preserves data' do
      expect(@service_client.read('test_key')).to eq('test_value')
    end
  end

  context 'when stopping the broker vm' do
    before(:all) do
      @prestop_timestamp = broker_ssh.execute("date +%s")
      bosh_director.stop(environment.bosh_service_broker_job_name, 0)
    end

    after(:all) do
      bosh_director.start(environment.bosh_service_broker_job_name, 0)
    end

    it 'logs redis broker shutdown' do
      expect(eventually_contains_shutdown_log(@prestop_timestamp)).to be true
    end
  end

  it_behaves_like 'a persistent cloud foundry service'

  describe 'redis configuration' do
    before(:all) do
      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @service_binding  = service_broker.bind_instance(@service_instance)
    end

    after(:all) do
      service_broker.unbind_instance(@service_binding)
      service_broker.deprovision_instance(@service_instance)
    end

    describe 'configuration' do
      it 'has the correct maxclients' do
        service_client = service_client_builder(@service_binding)
        expect(service_client.config.fetch('maxclients')).to eq("10000")
      end

      it 'has the correct maxmemory' do
        maxmemory = bosh_manifest.property('redis.maxmemory')
        service_client = service_client_builder(@service_binding)
        expect(service_client.config.fetch('maxmemory').to_i).to eq(maxmemory)
      end

      it 'runs correct version of redis' do
        service_client = service_client_builder(@service_binding)
        expect(service_client.info('redis_version')).to eq('3.2.8')
      end
    end

    describe 'pidfiles' do
      it 'do not appear in persistent storage' do
        persisted_pids = broker_ssh.execute('sudo find /var/vcap/store/ -name "redis-server.pid" 2>/dev/null')
        expect(persisted_pids.strip).to be_empty, "Actual output of find was: #{persisted_pids}"
      end

      it 'appear in ephemeral storage' do
        ephemeral_pids = broker_ssh.execute('sudo find /var/vcap/sys/run/shared-instance-pidfiles/ -name *.pid 2>/dev/null')
        expect(ephemeral_pids.strip).to_not be_empty
        expect(ephemeral_pids.lines.length).to eq(1), "Actual output of find was: #{ephemeral_pids}"
      end
    end
  end

  context 'when redis related properties changed in the manifest' do
    before do
      bosh_manifest.set_property('redis.config_command', 'configalias')
      bosh_director.deploy
    end

    after do
      bosh_manifest.set_property('redis.config_command', 'configalias')
      bosh_director.deploy
    end

    it 'updates existing instances' do
      service_broker.provision_and_bind(service.name, service.plan) do |service_binding|
        redis_client_1 = service_client_builder(service_binding)
        redis_client_1.write('test', 'foobar')
        original_config_command = redis_client_1.config_command

        bosh_manifest.set_property('redis.config_command', 'newconfigalias')
        bosh_director.deploy

        redis_client_2 = service_client_builder(service_binding)
        new_config_command = redis_client_2.config_command
        expect(original_config_command).to_not eq(new_config_command)
        expect(redis_client_2.read('test')).to eq('foobar')
      end
    end
  end

  context 'service broker' do
    let(:admin_command_availability) do
      {
        'BGSAVE' => false,
        'BGREWRITEAOF' => false,
        'MONITOR' => false,
        'SAVE' => false,
        'DEBUG' => false,
        'SHUTDOWN' => false,
        'SLAVEOF' => false,
        'SYNC' => false,
        'CONFIG' => false
      }
    end

    it_behaves_like 'a redis instance'
  end

  fcontext 'when repeatedly draining a redis instance' do
    before(:all) do
      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @service_binding  = service_broker.bind_instance(@service_instance)

      ps_output = broker_ssh.execute('sudo ps aux | grep redis-serve[r]')
      expect(ps_output.strip).not_to be_empty
      expect(ps_output.lines.length).to eq(1)

      drain_command = 'sudo /var/vcap/jobs/cf-redis-broker/bin/drain'
      broker_ssh.execute(drain_command)
      sleep 1

      ps_output = broker_ssh.execute('sudo ps aux | grep redis-serve[r]')
      expect(ps_output).to be_nil

      broker_ssh.execute('sudo /var/vcap/bosh/bin/monit restart process-watcher')

      expect(wait_for_process_start('process-watcher')).to eq(true)

      broker_ssh.execute(drain_command)
      sleep 1
    end

    after(:all) do
      broker_ssh.execute('sudo /var/vcap/bosh/bin/monit restart process-watcher')

      expect(wait_for_process_start('process-watcher')).to eq(true)

      service_broker.unbind_instance(@service_binding)
      service_broker.deprovision_instance(@service_instance)
    end

    it 'successfuly drained the redis instance' do
      ps_output = broker_ssh.execute('sudo ps aux | grep redis-serve[r]')
      expect(ps_output.strip).to be_empty
    end
  end

  describe 'process destroyer' do
    before do
      @service_instance = service_broker.provision_instance(service.name, service.plan)
      @service_binding  = service_broker.bind_instance(@service_instance)
      @vm_ip            = @service_binding.credentials[:host]

      ps_output = ssh_gateway.execute_on(@vm_ip, 'ps aux | grep redis-serve[r]')
      expect(ps_output).not_to be_nil
    end

    after do
      root_execute_on(@vm_ip, '/var/vcap/bosh/bin/monit restart process-watcher')

      expect(wait_for_process_start('process-watcher', @vm_ip)).to eq(true)

      service_broker.unbind_instance(@service_binding)
      service_broker.deprovision_instance(@service_instance)
    end

    it 'kills all redis-server processes when stopped' do
      root_execute_on(@vm_ip, '/var/vcap/bosh/bin/monit stop process-destroyer')

      wait_for_process_stop('process-destroyer')

      ps_output = ssh_gateway.execute_on(@vm_ip, 'ps aux | grep redis-serve[r]')
      expect(ps_output).to be_nil
    end
  end

  def process_not_monitored?(process_name)
    monit_output = root_execute_on(@vm_ip, "/var/vcap/bosh/bin/monit summary | grep #{process_name} | grep 'not monitored'")
    !monit_output.strip.empty?
  end

  def wait_for_process_stop(process_name)
    for _ in 0..12 do
      puts "Waiting for #{process_name} to stop"
      sleep 5
      return true if process_not_monitored?(process_name)
    end

    puts "Process #{process_name} did not stop within 60 seconds"
    return false
  end

  def eventually_contains_shutdown_log(prestop_timestamp)
    12.times do
      vm_log = broker_ssh.execute("sudo cat /var/log/syslog")
      contains_expected_shutdown_log = drop_log_lines_before(prestop_timestamp, vm_log).any? do |line|
        line.include?('Starting Redis Broker shutdown')
      end

      return true if contains_expected_shutdown_log
      sleep 5
    end

    false
  end
end
