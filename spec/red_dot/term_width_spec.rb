# frozen_string_literal: true

require 'red_dot/term_width'

RSpec.describe RedDot::TermWidth do
  describe '.of' do
    it 'strips ANSI and uses display width for wide characters' do
      expect(described_class.of("\e[31m测\e[0m试")).to eq(4)
    end
  end

  describe '.truncate' do
    it 'truncates to display width without splitting wide characters' do
      expect(described_class.truncate('测试ab', 3)).to eq('测')
      expect(described_class.truncate('测试ab', 4)).to eq('测试')
    end

    it 'preserves leading ANSI when truncating visible text' do
      s = "\e[31mhi\e[0m"
      expect(described_class.truncate(s, 1)).to eq("\e[31mh")
    end
  end
end
