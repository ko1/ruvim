# frozen_string_literal: true

module RuVim
  module Lang
    module Sql
      KEYWORDS = %w[
        SELECT FROM WHERE AND OR NOT IN IS NULL LIKE BETWEEN EXISTS
        INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE ALTER DROP
        INDEX VIEW TRIGGER FUNCTION PROCEDURE
        JOIN INNER LEFT RIGHT OUTER FULL CROSS ON USING
        GROUP BY ORDER ASC DESC HAVING LIMIT OFFSET DISTINCT
        UNION ALL INTERSECT EXCEPT AS CASE WHEN THEN ELSE END
        BEGIN COMMIT ROLLBACK TRANSACTION SAVEPOINT
        PRIMARY KEY FOREIGN REFERENCES UNIQUE CHECK DEFAULT CONSTRAINT
        IF ELSE ELSEIF WHILE LOOP FOR RETURN DECLARE
        INT INTEGER BIGINT SMALLINT TINYINT
        FLOAT DOUBLE DECIMAL NUMERIC REAL
        CHAR VARCHAR TEXT BLOB CLOB BOOLEAN DATE TIME TIMESTAMP
        SERIAL AUTO_INCREMENT IDENTITY
        CASCADE RESTRICT SET GRANT REVOKE WITH RECURSIVE
        COUNT SUM AVG MIN MAX COALESCE NULLIF CAST CONVERT
        EXPLAIN ANALYZE VACUUM REINDEX CLUSTER TRUNCATE
        TRUE FALSE
      ].freeze

      KEYWORD_RE = /\b(?:#{KEYWORDS.join("|")})\b/i
      STRING_SINGLE_RE = /'(?:''|[^'])*'/
      STRING_DOUBLE_RE = /"(?:""|[^"])*"/
      NUMBER_RE = /\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/
      LINE_COMMENT_RE = /--.*/
      BLOCK_COMMENT_RE = %r{/\*.*?\*/}
      PARAMETER_RE = /[:@$]\w+/

      module_function

      def color_columns(text)
        cols = {}
        Highlighter.apply_regex(cols, text, STRING_SINGLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, STRING_DOUBLE_RE, Highlighter::STRING_COLOR)
        Highlighter.apply_regex(cols, text, KEYWORD_RE, Highlighter::KEYWORD_COLOR)
        Highlighter.apply_regex(cols, text, NUMBER_RE, Highlighter::NUMBER_COLOR)
        Highlighter.apply_regex(cols, text, PARAMETER_RE, Highlighter::VARIABLE_COLOR)
        Highlighter.apply_regex(cols, text, BLOCK_COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        Highlighter.apply_regex(cols, text, LINE_COMMENT_RE, Highlighter::COMMENT_COLOR, override: true)
        cols
      end
    end
  end
end
