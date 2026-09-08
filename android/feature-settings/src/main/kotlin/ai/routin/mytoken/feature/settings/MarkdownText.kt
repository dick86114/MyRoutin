package ai.routin.mytoken.feature.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle

/**
 * 渲染 Release body 中常用的 Markdown 子集，避免把远程内容当作 HTML 或 Compose 内容执行。
 */
@Composable
internal fun MarkdownText(markdown: String) {
    Column {
        markdown.replace("\r\n", "\n").split('\n').forEach { line ->
            Text(
                text = markdownLine(line),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private fun markdownLine(line: String): AnnotatedString = buildAnnotatedString {
    val heading = Regex("^#{1,6}\\s+").find(line)
    if (heading != null) {
        withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
            append(line.removeRange(heading.range))
        }
        return@buildAnnotatedString
    }
    val content = line.replaceFirst(Regex("^\\s*[-*+]\\s+"), "• ")
    appendInlineMarkdown(content)
}

private fun AnnotatedString.Builder.appendInlineMarkdown(value: String) {
    val token = Regex("(\\*\\*|__)(.+?)\\1|(`)(.+?)\\3|(\\[(.+?)])\\((.+?)\\)")
    var cursor = 0
    token.findAll(value).forEach { match ->
        append(value.substring(cursor, match.range.first))
        when {
            match.groupValues[1].isNotEmpty() -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                append(match.groupValues[2])
            }
            match.groupValues[3].isNotEmpty() -> withStyle(
                SpanStyle(fontFamily = FontFamily.Monospace),
            ) { append(match.groupValues[4]) }
            else -> withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) {
                append(match.groupValues[6])
            }
        }
        cursor = match.range.last + 1
    }
    append(value.substring(cursor))
}
