from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
QML_FILES = (ROOT / "BarWidget.qml", ROOT / "SummaryPanel.qml", ROOT / "TryStation.qml")
SAFE_TEXT_COMPONENT = """component SafeText: Text {
    textFormat: Text.PlainText
  }"""


class QmlTextSafetyTest(unittest.TestCase):
    def test_text_labels_do_not_use_automatic_rich_text_detection(self):
        for path in QML_FILES:
            source = path.read_text()
            source_without_safe_component = source.replace(SAFE_TEXT_COMPONENT, "")
            with self.subTest(path=path.name):
                self.assertIsNone(
                    re.search(r"(?<![A-Za-z])Text\s*\{", source_without_safe_component),
                    f"{path.name} contains a Text sink without explicit PlainText handling",
                )

    def test_editable_notes_are_plain_text(self):
        source = (ROOT / "TryStation.qml").read_text()
        self.assertIn("textFormat: TextEdit.PlainText", source)

    def test_dynamic_shared_controls_neutralize_markup_delimiters(self):
        source = (ROOT / "TryStation.qml").read_text()
        self.assertIn("text: root.plainForAutoText(modelData.toUpperCase())", source)
        self.assertIn(
            'root.plainForAutoText(root.activeSession ? root.activeSession.title : "this try")',
            source,
        )


if __name__ == "__main__":
    unittest.main()
