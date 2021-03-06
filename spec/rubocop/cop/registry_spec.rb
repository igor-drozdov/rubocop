# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Registry do
  subject(:registry) { described_class.new(cops) }

  let(:cops) do
    stub_const('RuboCop::Cop::Test', Module.new)
    stub_const('RuboCop::Cop::RSpec', Module.new)

    module RuboCop
      module Cop
        module Test
          # Create another cop with a different namespace
          class FirstArrayElementIndentation < Cop
          end
        end

        module RSpec
          # Define a dummy rspec cop which has special namespace inflection
          class Foo < Cop
          end
        end
      end
    end

    [
      RuboCop::Cop::Lint::BooleanSymbol,
      RuboCop::Cop::Lint::DuplicateMethods,
      RuboCop::Cop::Layout::FirstArrayElementIndentation,
      RuboCop::Cop::Metrics::MethodLength,
      RuboCop::Cop::RSpec::Foo,
      RuboCop::Cop::Test::FirstArrayElementIndentation
    ]
  end

  # `RuboCop::Cop::Cop` mutates its `registry` when inherited from.
  # This can introduce nondeterministic failures in other parts of the
  # specs if this mutation occurs before code that depends on this global cop
  # store. The workaround is to replace the global cop store with a temporary
  # store during these tests
  around do |test|
    registry        = RuboCop::Cop::Cop.registry
    temporary_store = described_class.new(registry.cops)
    RuboCop::Cop::Cop.instance_variable_set(:@registry, temporary_store)

    test.run

    RuboCop::Cop::Cop.instance_variable_set(:@registry, registry)
  end

  it 'exposes cop departments' do
    expect(registry.departments).to eql(%i[Lint Layout Metrics RSpec Test])
  end

  it 'can filter down to one type' do
    expect(registry.with_department(:Lint))
      .to eq(described_class.new(cops.first(2)))
  end

  it 'can filter down to all but one type' do
    expect(registry.without_department(:Lint))
      .to eq(described_class.new(cops.drop(2)))
  end

  context '#contains_cop_matching?' do
    it 'can find cops matching a given name' do
      result = registry.contains_cop_matching?(
        ['Test/FirstArrayElementIndentation']
      )
      expect(result).to be(true)
    end

    it 'returns false for cops not included in the store' do
      expect(registry.contains_cop_matching?(['Style/NotReal'])).to be(false)
    end
  end

  context '#qualified_cop_name' do
    let(:origin) { '/app/.rubocop.yml' }

    it 'gives back already properly qualified names' do
      result = registry.qualified_cop_name(
        'Layout/FirstArrayElementIndentation',
        origin
      )
      expect(result).to eql('Layout/FirstArrayElementIndentation')
    end

    it 'qualifies names without a namespace' do
      warning =
        "/app/.rubocop.yml: Warning: no department given for MethodLength.\n"
      qualified = nil

      expect do
        qualified = registry.qualified_cop_name('MethodLength', origin)
      end.to output(warning).to_stderr

      expect(qualified).to eql('Metrics/MethodLength')
    end

    it 'qualifies names with the correct namespace' do
      warning = "/app/.rubocop.yml: Warning: no department given for Foo.\n"
      qualified = nil

      expect do
        qualified = registry.qualified_cop_name('Foo', origin)
      end.to output(warning).to_stderr

      expect(qualified).to eql('RSpec/Foo')
    end

    it 'emits a warning when namespace is incorrect' do
      warning = '/app/.rubocop.yml: Style/MethodLength has the wrong ' \
                "namespace - should be Metrics\n"
      qualified = nil

      expect do
        qualified = registry.qualified_cop_name('Style/MethodLength', origin)
      end.to output(warning).to_stderr

      expect(qualified).to eql('Metrics/MethodLength')
    end

    it 'raises an error when a cop name is ambiguous' do
      cop_name = 'FirstArrayElementIndentation'
      expect { registry.qualified_cop_name(cop_name, origin) }
        .to raise_error(RuboCop::Cop::AmbiguousCopName)
        .with_message(
          'Ambiguous cop name `FirstArrayElementIndentation` used in ' \
          '/app/.rubocop.yml needs department qualifier. Did you mean ' \
          'Layout/FirstArrayElementIndentation or ' \
          'Test/FirstArrayElementIndentation?'
        )
        .and output('/app/.rubocop.yml: Warning: no department given for ' \
                    "FirstArrayElementIndentation.\n").to_stderr
    end

    it 'returns the provided name if no namespace is found' do
      expect(registry.qualified_cop_name('NotReal', origin)).to eql('NotReal')
    end
  end

  it 'exposes a mapping of cop names to cop classes' do
    expect(registry.to_h).to eql(
      'Lint/BooleanSymbol' => [RuboCop::Cop::Lint::BooleanSymbol],
      'Lint/DuplicateMethods' => [RuboCop::Cop::Lint::DuplicateMethods],
      'Layout/FirstArrayElementIndentation' => [
        RuboCop::Cop::Layout::FirstArrayElementIndentation
      ],
      'Metrics/MethodLength' => [RuboCop::Cop::Metrics::MethodLength],
      'Test/FirstArrayElementIndentation' => [
        RuboCop::Cop::Test::FirstArrayElementIndentation
      ],
      'RSpec/Foo' => [RuboCop::Cop::RSpec::Foo]
    )
  end

  context '#cops' do
    it 'exposes a list of cops' do
      expect(registry.cops).to eql(cops)
    end
  end

  it 'exposes the number of stored cops' do
    expect(registry.length).to be(6)
  end

  context '#enabled' do
    let(:config) do
      RuboCop::Config.new(
        'Test/FirstArrayElementIndentation' => { 'Enabled' => false },
        'RSpec/Foo' => { 'Safe' => false }
      )
    end

    it 'selects cops which are enabled in the config' do
      expect(registry.enabled(config, [])).to eql(cops.first(5))
    end

    it 'overrides config if :only includes the cop' do
      result = registry.enabled(config, ['Test/FirstArrayElementIndentation'])
      expect(result).to eql(cops)
    end

    it 'selects only safe cops if :safe passed' do
      enabled_cops = registry.enabled(config, [], true)
      expect(enabled_cops).not_to include(RuboCop::Cop::RSpec::Foo)
    end
  end

  it 'exposes a list of cop names' do
    expect(registry.names).to eql(
      [
        'Lint/BooleanSymbol',
        'Lint/DuplicateMethods',
        'Layout/FirstArrayElementIndentation',
        'Metrics/MethodLength',
        'RSpec/Foo',
        'Test/FirstArrayElementIndentation'
      ]
    )
  end
end
