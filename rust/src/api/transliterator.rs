//! The yangi-alifbo engine for Dart. It has the same four functions, and its offsets count UTF-16 code units, the way
//! Dart strings index, so `text.substring(change.start, change.end)` is `change.original`. `convert_docx` converts a
//! Word document, and `convert_office` any Word or Excel file, old or new.

use flutter_rust_bridge::frb;
use yangi_alifbo::utf16;

/// Which scripts to convert. Both, unless told otherwise.
#[frb]
pub struct Options {
    /// Old Latin letters: Oʻ, Gʻ, Sh and Ch.
    #[frb(default = true)]
    pub old_latin: bool,
    /// Uzbek Cyrillic words.
    #[frb(default = true)]
    pub cyrillic: bool,
}

/// What a change converts: a Latin word with old letters, or a Cyrillic word.
pub enum ChangeKind {
    OldLatin,
    Cyrillic,
}

/// Why a change is left as typed: part of a web address or e-mail, or a Latin word with a letter Uzbek does not use.
pub enum SkipReason {
    Link,
    NotUzbek,
}

/// A word that the new alphabet spells differently. `start` and `end` are UTF-16 offsets.
pub struct Change {
    pub kind: ChangeKind,
    pub start: u32,
    pub end: u32,
    pub original: String,
    pub replacement: String,
    /// Set when the change is left as typed.
    pub skip: Option<SkipReason>,
}

/// What a list of changes converts and leaves as typed.
pub struct Summary {
    pub old_letters: u32,
    pub cyrillic_words: u32,
    pub skipped: u32,
}

/// A Word document with its text in the new alphabet, and what was converted.
pub struct ConvertedDocx {
    /// The converted document.
    pub docx: Vec<u8>,
    pub summary: Summary,
}

/// Why a Word document could not be converted.
pub enum DocxError {
    /// Not a Word document: not a zip file, or one without a Word body, such as an old .doc or a password-protected file.
    NotWord,
    /// A Word document whose zip file or XML is broken.
    Damaged,
}

/// What kind of file `convert_office` found, and wrote.
pub enum OfficeFormat {
    /// Word: .docx.
    Docx,
    /// Excel: .xlsx.
    Xlsx,
    /// Excel 97–2003: .xls.
    Xls,
    /// Word 97–2003: .doc.
    Doc,
}

/// A Word or Excel file with its text in the new alphabet, and what was converted.
pub struct ConvertedOffice {
    pub format: OfficeFormat,
    /// The converted file, of the same kind as the one given.
    pub bytes: Vec<u8>,
    pub summary: Summary,
}

/// Why a Word or Excel file could not be converted.
pub enum OfficeError {
    /// Not a Word or Excel file.
    NotOffice,
    /// A kind of file that is not converted, such as an Excel binary workbook (.xlsb) or a Word 6 or 95 document.
    Unsupported,
    /// A password-protected file.
    Encrypted,
    /// A file whose zip file, XML or records are broken.
    Damaged,
    /// A file with something in it that cannot be rewritten safely, such as tracked deletions in an old .doc.
    Refused,
}

/// Writes the text in the new alphabet, leaving out the changes `analyze` marks as skipped.
#[frb]
pub fn convert(text: String, #[frb(default = "const Options()")] options: Options) -> String {
    yangi_alifbo::convert(&text, engine_options(options))
}

/// Finds every word the new alphabet spells differently, in text order.
#[frb]
pub fn analyze(text: String, #[frb(default = "const Options()")] options: Options) -> Vec<Change> {
    let changes = yangi_alifbo::analyze(&text, engine_options(options));
    let bytes: Vec<usize> = changes
        .iter()
        .flat_map(|change| [change.start, change.end])
        .collect();
    let units = utf16::from_byte_offsets(&text, &bytes);
    changes
        .into_iter()
        .zip(units.chunks(2))
        .map(|(change, range)| Change {
            kind: change.kind.into(),
            start: dart_int(range[0]),
            end: dart_int(range[1]),
            original: change.original,
            replacement: change.replacement,
            skip: change.skip.map(Into::into),
        })
        .collect()
}

/// Writes the given changes into the text, skipped or not. A change that no longer fits the text is left out.
pub fn apply(text: String, changes: Vec<Change>) -> String {
    let units: Vec<usize> = changes
        .iter()
        .flat_map(|change| [change.start as usize, change.end as usize])
        .collect();
    let bytes = utf16::to_byte_offsets(&text, &units);
    let changes: Vec<yangi_alifbo::Change> = changes
        .into_iter()
        .zip(bytes.chunks(2))
        .filter_map(|(change, range)| Some(engine_change(change, range[0]?, range[1]?)))
        .collect();
    yangi_alifbo::apply(&text, &changes)
}

/// Counts what the changes convert, as `convert` would write them, and how many are skipped.
pub fn summarize(changes: Vec<Change>) -> Summary {
    // The counts do not depend on where the changes are.
    let changes: Vec<yangi_alifbo::Change> = changes
        .into_iter()
        .map(|change| engine_change(change, 0, 0))
        .collect();
    yangi_alifbo::summarize(&changes).into()
}

/// Writes the text of a Word document (.docx) in the new alphabet. Everything else in the file stays as it was.
#[frb]
pub fn convert_docx(
    docx: Vec<u8>,
    #[frb(default = "const Options()")] options: Options,
) -> Result<ConvertedDocx, DocxError> {
    let converted = yangi_alifbo::docx::convert(&docx, engine_options(options)).map_err(
        |error| match error {
            yangi_alifbo::docx::Error::NotWord => DocxError::NotWord,
            _ => DocxError::Damaged,
        },
    )?;
    Ok(ConvertedDocx {
        summary: converted.summary().into(),
        docx: converted.docx,
    })
}

/// Writes the text of a Word or Excel file in the new alphabet, whatever kind it is: .docx, .xlsx, .doc or .xls. The kind
/// is read from the bytes, not from a name. Everything else in the file stays as it was, and every text of a workbook
/// converts.
#[frb]
pub fn convert_office(
    bytes: Vec<u8>,
    #[frb(default = "const Options()")] options: Options,
) -> Result<ConvertedOffice, OfficeError> {
    use yangi_alifbo::office::{self, Error, Format};

    let output = office::convert(&bytes, engine_options(options)).map_err(|error| match error {
        Error::Not(_) | Error::Unknown => OfficeError::NotOffice,
        Error::Unsupported(_) => OfficeError::Unsupported,
        Error::Encrypted => OfficeError::Encrypted,
        Error::Refused(_) => OfficeError::Refused,
        _ => OfficeError::Damaged,
    })?;
    let format = match output.format {
        Format::Docx => OfficeFormat::Docx,
        Format::Xlsx => OfficeFormat::Xlsx,
        Format::Xls => OfficeFormat::Xls,
        Format::Doc => OfficeFormat::Doc,
        _ => return Err(OfficeError::Damaged),
    };
    Ok(ConvertedOffice {
        format,
        summary: output.summary().into(),
        bytes: output.bytes,
    })
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

fn engine_options(options: Options) -> yangi_alifbo::Options {
    yangi_alifbo::Options {
        old_latin: options.old_latin,
        cyrillic: options.cyrillic,
    }
}

fn engine_change(change: Change, start: usize, end: usize) -> yangi_alifbo::Change {
    yangi_alifbo::Change {
        kind: change.kind.into(),
        start,
        end,
        original: change.original,
        replacement: change.replacement,
        skip: change.skip.map(Into::into),
    }
}

// A Dart int for an offset or a count; no text comes near u32::MAX.
fn dart_int(number: usize) -> u32 {
    u32::try_from(number).unwrap_or(u32::MAX)
}

impl From<yangi_alifbo::Summary> for Summary {
    fn from(summary: yangi_alifbo::Summary) -> Self {
        Summary {
            old_letters: dart_int(summary.old_letters),
            cyrillic_words: dart_int(summary.cyrillic_words),
            skipped: dart_int(summary.skipped),
        }
    }
}

impl From<yangi_alifbo::ChangeKind> for ChangeKind {
    fn from(kind: yangi_alifbo::ChangeKind) -> Self {
        match kind {
            yangi_alifbo::ChangeKind::OldLatin => ChangeKind::OldLatin,
            yangi_alifbo::ChangeKind::Cyrillic => ChangeKind::Cyrillic,
        }
    }
}

impl From<ChangeKind> for yangi_alifbo::ChangeKind {
    fn from(kind: ChangeKind) -> Self {
        match kind {
            ChangeKind::OldLatin => yangi_alifbo::ChangeKind::OldLatin,
            ChangeKind::Cyrillic => yangi_alifbo::ChangeKind::Cyrillic,
        }
    }
}

impl From<yangi_alifbo::SkipReason> for SkipReason {
    fn from(reason: yangi_alifbo::SkipReason) -> Self {
        match reason {
            yangi_alifbo::SkipReason::Link => SkipReason::Link,
            yangi_alifbo::SkipReason::NotUzbek => SkipReason::NotUzbek,
        }
    }
}

impl From<SkipReason> for yangi_alifbo::SkipReason {
    fn from(reason: SkipReason) -> Self {
        match reason {
            SkipReason::Link => yangi_alifbo::SkipReason::Link,
            SkipReason::NotUzbek => yangi_alifbo::SkipReason::NotUzbek,
        }
    }
}
