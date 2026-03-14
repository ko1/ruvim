#!/usr/bin/env ruby
# frozen_string_literal: true

# docs/tutorial_book.md → docs/tutorial_book.html
# Usage: ruby docs/generate_html.rb

require "cgi"

INPUT  = File.join(__dir__, "tutorial_book.md")
OUTPUT = File.join(__dir__, "tutorial_book.html")

markdown = File.read(INPUT, encoding: "utf-8")

# --- Markdown → HTML (minimal converter) ---

class MarkdownToHTML
  def initialize(md)
    @md = md
    @toc = []       # [{level:, id:, text:}]
    @html_lines = []
    @in_code = false
    @in_table = false
    @in_list = false
    @in_blockquote = false
    @code_lang = nil
  end

  def convert
    lines = @md.lines.map(&:chomp)
    i = 0
    while i < lines.size
      line = lines[i]

      # Fenced code block
      if line.match?(/\A```/)
        if @in_code
          @html_lines << "</code></pre>"
          @in_code = false
        else
          close_contexts
          lang = line.sub(/\A```\s*/, "").strip
          lang_attr = lang.empty? ? "" : %( class="language-#{esc(lang)}")
          @html_lines << "<pre><code#{lang_attr}>"
          @in_code = true
        end
        i += 1
        next
      end

      if @in_code
        @html_lines << esc(line)
        i += 1
        next
      end

      # Blank line
      if line.strip.empty?
        close_list if @in_list
        close_table if @in_table
        close_blockquote if @in_blockquote
        i += 1
        next
      end

      # HR
      if line.match?(/\A-{3,}\s*\z/)
        close_contexts
        @html_lines << "<hr>"
        i += 1
        next
      end

      # Heading
      if (m = line.match(/\A(\#{1,6})\s+(.+)/))
        close_contexts
        level = m[1].size
        text = m[2].strip
        id = make_id(text)
        @toc << { level: level, id: id, text: text }
        @html_lines << %(<h#{level} id="#{esc(id)}">#{inline(text)}</h#{level}>)
        i += 1
        next
      end

      # Blockquote
      if line.start_with?("> ")
        unless @in_blockquote
          close_contexts
          @html_lines << "<blockquote>"
          @in_blockquote = true
        end
        @html_lines << "<p>#{inline(line.sub(/\A>\s?/, ""))}</p>"
        i += 1
        next
      end

      # Table
      if line.include?("|") && line.strip.start_with?("|")
        unless @in_table
          close_contexts
          # Check if next line is separator
          if i + 1 < lines.size && lines[i + 1].match?(/\A\|[\s\-:|]+\|\s*\z/)
            @html_lines << "<table>"
            @html_lines << "<thead><tr>"
            parse_table_row(line).each { |cell| @html_lines << "<th>#{inline(cell)}</th>" }
            @html_lines << "</tr></thead>"
            @html_lines << "<tbody>"
            @in_table = true
            i += 2 # skip header + separator
            next
          else
            @html_lines << "<table><tbody>"
            @in_table = true
          end
        end
        @html_lines << "<tr>"
        parse_table_row(line).each { |cell| @html_lines << "<td>#{inline(cell)}</td>" }
        @html_lines << "</tr>"
        i += 1
        next
      end

      # Unordered list
      if line.match?(/\A\s*[-*]\s/)
        unless @in_list
          close_contexts
          @html_lines << "<ul>"
          @in_list = true
        end
        content = line.sub(/\A\s*[-*]\s+/, "")
        @html_lines << "<li>#{inline(content)}</li>"
        i += 1
        next
      end

      # Ordered list
      if line.match?(/\A\s*\d+\.\s/)
        unless @in_list
          close_contexts
          @html_lines << "<ol>"
          @in_list = true
        end
        content = line.sub(/\A\s*\d+\.\s+/, "")
        @html_lines << "<li>#{inline(content)}</li>"
        i += 1
        next
      end

      # Paragraph
      close_contexts
      para = [line]
      while i + 1 < lines.size && !lines[i + 1].strip.empty? &&
            !lines[i + 1].match?(/\A\#{1,6}\s/) &&
            !lines[i + 1].match?(/\A```/) &&
            !lines[i + 1].match?(/\A-{3,}\s*\z/) &&
            !lines[i + 1].match?(/\A\s*[-*]\s/) &&
            !lines[i + 1].match?(/\A\s*\d+\.\s/) &&
            !(lines[i + 1].include?("|") && lines[i + 1].strip.start_with?("|")) &&
            !lines[i + 1].start_with?("> ")
        i += 1
        para << lines[i]
      end
      @html_lines << "<p>#{inline(para.join(" "))}</p>"
      i += 1
    end
    close_contexts

    @html_lines.join("\n")
  end

  def toc
    @toc
  end

  private

  def close_contexts
    close_list if @in_list
    close_table if @in_table
    close_blockquote if @in_blockquote
  end

  def close_list
    # detect if last <ol> or <ul>
    # search backward
    tag = @html_lines.reverse.find { |l| l == "<ul>" || l == "<ol>" }
    close = tag == "<ol>" ? "</ol>" : "</ul>"
    @html_lines << close
    @in_list = false
  end

  def close_table
    @html_lines << "</tbody></table>"
    @in_table = false
  end

  def close_blockquote
    @html_lines << "</blockquote>"
    @in_blockquote = false
  end

  def esc(s)
    CGI.escapeHTML(s)
  end

  def inline(text)
    s = esc(text)
    # Bold
    s = s.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
    # Italic
    s = s.gsub(/\*(.+?)\*/, '<em>\1</em>')
    # Inline code
    s = s.gsub(/``(.+?)``/, '<code>\1</code>')
    s = s.gsub(/`(.+?)`/, '<code>\1</code>')
    # Links
    s = s.gsub(/\[(.+?)\]\((.+?)\)/, '<a href="\2">\1</a>')
    s
  end

  def make_id(text)
    @id_counts ||= Hash.new(0)
    base = text.downcase
               .gsub(/[^\w\s\u3000-\u9fff\u{f900}-\u{faff}.-]/, "")
               .gsub(/\s+/, "-")
               .gsub(/-+/, "-")
               .gsub(/\A-|-\z/, "")
    count = @id_counts[base] += 1
    count == 1 ? base : "#{base}-#{count}"
  end

  def parse_table_row(line)
    cells = line.strip.sub(/\A\|/, "").sub(/\|\s*\z/, "").split("|")
    cells.map(&:strip)
  end
end

converter = MarkdownToHTML.new(markdown)
body_html = converter.convert
toc = converter.toc

# --- Build sidebar ---

def build_toc_html(toc)
  lines = []
  toc.each do |entry|
    next if entry[:level] > 3
    indent = entry[:level] - 1
    cls = "toc-h#{entry[:level]}"
    lines << %(<a class="#{cls}" href="##{CGI.escapeHTML(entry[:id])}">#{CGI.escapeHTML(entry[:text])}</a>)
  end
  lines.join("\n")
end

toc_html = build_toc_html(toc)

# --- Final HTML ---

html = <<~HTML
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>RuVim 完全ガイド — チュートリアルブック</title>
<style>
  :root {
    --sidebar-width: 300px;
    --bg: #fff;
    --sidebar-bg: #f8f9fa;
    --border: #e1e4e8;
    --text: #24292e;
    --text-secondary: #586069;
    --link: #0366d6;
    --code-bg: #f6f8fa;
    --active-bg: #e8f0fe;
    --heading-color: #1a1a2e;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0d1117;
      --sidebar-bg: #161b22;
      --border: #30363d;
      --text: #c9d1d9;
      --text-secondary: #8b949e;
      --link: #58a6ff;
      --code-bg: #1c2128;
      --active-bg: #1f2a3a;
      --heading-color: #e6edf3;
    }
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html { scroll-behavior: smooth; scroll-padding-top: 20px; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    color: var(--text);
    background: var(--bg);
    line-height: 1.7;
  }

  /* Sidebar */
  .sidebar {
    position: fixed;
    top: 0; left: 0;
    width: var(--sidebar-width);
    height: 100vh;
    overflow-y: auto;
    background: var(--sidebar-bg);
    border-right: 1px solid var(--border);
    padding: 16px 0;
    z-index: 10;
    scrollbar-width: thin;
  }
  .sidebar-title {
    font-size: 15px;
    font-weight: 700;
    padding: 8px 20px 16px;
    color: var(--heading-color);
    border-bottom: 1px solid var(--border);
    margin-bottom: 8px;
  }
  .sidebar a {
    display: block;
    padding: 4px 20px;
    color: var(--text-secondary);
    text-decoration: none;
    font-size: 13px;
    line-height: 1.5;
    border-left: 3px solid transparent;
    transition: all 0.15s;
  }
  .sidebar a:hover {
    color: var(--link);
    background: var(--active-bg);
  }
  .sidebar a.active {
    color: var(--link);
    border-left-color: var(--link);
    background: var(--active-bg);
    font-weight: 600;
  }
  .toc-h1 { font-weight: 700; font-size: 14px; color: var(--heading-color); margin-top: 12px; padding-top: 8px; }
  .toc-h2 { padding-left: 28px; }
  .toc-h3 { padding-left: 40px; font-size: 12px; }

  /* Main content */
  .content {
    margin-left: var(--sidebar-width);
    max-width: 820px;
    padding: 40px 48px 120px;
  }

  h1 { font-size: 2em; margin: 48px 0 16px; color: var(--heading-color); border-bottom: 2px solid var(--border); padding-bottom: 8px; }
  h2 { font-size: 1.5em; margin: 40px 0 12px; color: var(--heading-color); border-bottom: 1px solid var(--border); padding-bottom: 6px; }
  h3 { font-size: 1.2em; margin: 28px 0 8px; color: var(--heading-color); }
  h4 { font-size: 1em; margin: 20px 0 6px; color: var(--heading-color); }

  p { margin: 10px 0; }
  hr { border: none; border-top: 2px solid var(--border); margin: 48px 0; }

  a { color: var(--link); text-decoration: none; }
  a:hover { text-decoration: underline; }

  code {
    font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
    background: var(--code-bg);
    padding: 2px 6px;
    border-radius: 4px;
    font-size: 0.88em;
  }
  pre {
    background: var(--code-bg);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 16px;
    overflow-x: auto;
    margin: 12px 0;
    line-height: 1.5;
  }
  pre code {
    background: none;
    padding: 0;
    border-radius: 0;
    font-size: 0.85em;
  }

  table {
    border-collapse: collapse;
    width: 100%;
    margin: 12px 0;
    font-size: 0.92em;
  }
  th, td {
    border: 1px solid var(--border);
    padding: 8px 12px;
    text-align: left;
  }
  th { background: var(--code-bg); font-weight: 600; }
  tr:nth-child(even) { background: var(--sidebar-bg); }

  ul, ol { margin: 8px 0; padding-left: 28px; }
  li { margin: 4px 0; }

  blockquote {
    border-left: 4px solid var(--link);
    padding: 8px 16px;
    margin: 12px 0;
    color: var(--text-secondary);
    background: var(--sidebar-bg);
    border-radius: 0 4px 4px 0;
  }

  strong { font-weight: 600; }

  /* Back to top */
  .back-top {
    position: fixed;
    bottom: 24px;
    right: 24px;
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background: var(--link);
    color: #fff;
    border: none;
    cursor: pointer;
    font-size: 20px;
    display: none;
    align-items: center;
    justify-content: center;
    box-shadow: 0 2px 8px rgba(0,0,0,0.2);
    z-index: 20;
  }
  .back-top.show { display: flex; }

  /* Mobile */
  .menu-btn {
    display: none;
    position: fixed;
    top: 12px; left: 12px;
    z-index: 30;
    background: var(--sidebar-bg);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 8px 12px;
    cursor: pointer;
    font-size: 18px;
  }
  @media (max-width: 768px) {
    .sidebar { transform: translateX(-100%); transition: transform 0.25s; }
    .sidebar.open { transform: translateX(0); }
    .content { margin-left: 0; padding: 60px 20px 120px; }
    .menu-btn { display: block; }
  }
</style>
</head>
<body>

<button class="menu-btn" onclick="document.querySelector('.sidebar').classList.toggle('open')" aria-label="Menu">☰</button>

<nav class="sidebar" id="sidebar">
  <div class="sidebar-title">RuVim 完全ガイド</div>
  #{toc_html}
</nav>

<main class="content">
#{body_html}
</main>

<button class="back-top" id="backTop" onclick="window.scrollTo({top:0})" aria-label="Back to top">↑</button>

<script>
// Back to top button
const backTop = document.getElementById('backTop');
window.addEventListener('scroll', () => {
  backTop.classList.toggle('show', window.scrollY > 400);
});

// Active sidebar link tracking
const headings = document.querySelectorAll('h1[id], h2[id], h3[id]');
const links = document.querySelectorAll('.sidebar a');
const linkMap = {};
links.forEach(a => {
  const href = a.getAttribute('href');
  if (href) linkMap[href.slice(1)] = a;
});

let ticking = false;
function updateActive() {
  let current = '';
  headings.forEach(h => {
    if (h.getBoundingClientRect().top <= 60) current = h.id;
  });
  links.forEach(a => a.classList.remove('active'));
  if (current && linkMap[current]) {
    linkMap[current].classList.add('active');
    // Only auto-scroll sidebar when it is visible on screen (desktop)
    if (window.innerWidth > 768) {
      linkMap[current].scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }
  ticking = false;
}
window.addEventListener('scroll', () => {
  if (!ticking) { requestAnimationFrame(updateActive); ticking = true; }
});
updateActive();

// Close sidebar on mobile when clicking a link
document.querySelectorAll('.sidebar a').forEach(a => {
  a.addEventListener('click', () => {
    if (window.innerWidth <= 768) {
      document.querySelector('.sidebar').classList.remove('open');
    }
  });
});
</script>
</body>
</html>
HTML

File.write(OUTPUT, html, encoding: "utf-8")
puts "Generated: #{OUTPUT}"
puts "  TOC entries: #{toc.size}"
puts "  HTML size: #{File.size(OUTPUT)} bytes"
puts
puts "Open in browser:"
puts "  xdg-open #{OUTPUT}"
puts "  open #{OUTPUT}"
