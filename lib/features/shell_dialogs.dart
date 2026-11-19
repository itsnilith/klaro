import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/course_import.dart';
import '../core/db.dart';
import '../core/models.dart';
import '../core/state.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import 'shell.dart';

const _uuid = Uuid();

Future<String?> pickCoverImageFile({String dialogTitle = 'Choose a cover image'}) async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
    dialogTitle: dialogTitle,
  );
  return res?.files.single.path;
}

Future<void> showCourseEditor(BuildContext context, {Course? course}) async {
  final title = TextEditingController(text: course?.title ?? '');
  final author = TextEditingController(text: course?.author ?? '');
  final category = TextEditingController(text: course?.category ?? '');
  final description = TextEditingController(text: course?.description ?? '');
  final objectives = TextEditingController(text: course?.objectives ?? '');
  var coverPath = course?.cover;
  final saved = await showMSheet<bool>(
    context,
    maxWidth: 580,
    child: StatefulBuilder(
      builder: (context, setState) {
        final c = context.c;
        final hasCover = coverPath != null && coverPath!.isNotEmpty && File(coverPath!).existsSync();
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MDialogHeader(
                title: course == null ? 'New course' : 'Edit course',
                subtitle: 'Set the title, author, cover image and study goals for this course.',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(MRadius.md),
                          child: Container(
                            width: 120,
                            height: 76,
                            decoration: BoxDecoration(
                              color: c.surfaceSunken,
                              borderRadius: BorderRadius.circular(MRadius.md),
                              border: Border.all(color: c.line),
                            ),
                            child: hasCover
                                ? Image.file(File(coverPath!), fit: BoxFit.cover)
                                : Icon(Icons.image_outlined, size: 24, color: c.inkMuted),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Course cover',
                                style: MType.label.copyWith(color: c.inkMuted, fontSize: 10),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  MButton(
                                    label: hasCover ? 'Change cover' : 'Choose cover',
                                    icon: Icons.image_outlined,
                                    dense: true,
                                    onPressed: () async {
                                      final picked = await pickCoverImageFile(
                                        dialogTitle: 'Choose course cover',
                                      );
                                      if (picked != null) {
                                        setState(() => coverPath = picked);
                                      }
                                    },
                                  ),
                                  if (coverPath != null && coverPath!.isNotEmpty)
                                    MButton(
                                      label: 'Remove',
                                      icon: Icons.close_rounded,
                                      kind: MButtonKind.ghost,
                                      dense: true,
                                      onPressed: () => setState(() => coverPath = null),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _Field(label: 'Title', controller: title, hint: 'e.g. Linear Algebra'),
                    Row(
                      children: [
                        Expanded(
                          child: _Field(
                            label: 'Author / Instructor',
                            controller: author,
                            hint: 'e.g. Alessandro',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Field(
                            label: 'Category',
                            controller: category,
                            hint: 'Optional',
                          ),
                        ),
                      ],
                    ),
                    _Field(
                      label: 'Description',
                      controller: description,
                      hint: 'What is this course about?',
                      lines: 3,
                    ),
                    _Field(
                      label: 'Learning objectives',
                      controller: objectives,
                      hint: 'One per line. Used by the tutor and review generator.',
                      lines: 3,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    MButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop(false)),
                    const SizedBox(width: 8),
                    MButton(
                      label: course == null ? 'Create course' : 'Save changes',
                      kind: MButtonKind.primary,
                      onPressed: () {
                        if (title.text.trim().isEmpty) return;
                        Navigator.of(context).pop(true);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  if (saved != true) return;
  final now = DateTime.now();
  final c = course ??
      Course(
        id: _uuid.v4(),
        title: title.text.trim(),
        createdAt: now,
        updatedAt: now,
      );
  await Store.i.saveCourse(c.copyWith(
    title: title.text.trim(),
    author: author.text.trim().isEmpty ? null : author.text.trim(),
    category: category.text.trim().isEmpty ? null : category.text.trim(),
    description: description.text.trim().isEmpty ? null : description.text.trim(),
    objectives: objectives.text.trim().isEmpty ? null : objectives.text.trim(),
    cover: coverPath,
    clearCover: coverPath == null,
    updatedAt: now,
  ));
  AppState.i.bump();
}

Future<void> importCourseFolder(BuildContext context) async {
  final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose a course folder');
  if (dir == null) return;
  final result = await importCourseFromFolder(dir);
  if (!context.mounted) return;
  if (result == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No supported lessons or documents were found in that folder.')),
    );
    return;
  }
  AppState.i.bump();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Imported ${result.lessonCount} lessons and ${result.documentCount} files. '
        'Original files were not moved.',
      ),
    ),
  );
  await Nav.course(context, result.course.id);
}

Future<void> showNoteEditor(
  BuildContext context, {
  Note? note,
  String? courseId,
  String? lessonId,
  String? resourceId,
  int? page,
  int? timestampMs,
  String? initialBody,
}) async {
  final title = TextEditingController(text: note?.title ?? '');
  final body = TextEditingController(text: note?.body ?? initialBody ?? '');
  final saved = await showMSheet<bool>(
    context,
    maxWidth: 640,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MDialogHeader(
          title: note == null ? 'New note' : 'Edit note',
          subtitle: 'Markdown is supported. Notes stay linked to their source.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Column(
            children: [
              _Field(label: 'Title', controller: title, hint: 'Give this note a name'),
              _Field(label: 'Note', controller: body, hint: 'Write in your own words…', lines: 10),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              MButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop(false)),
              const SizedBox(width: 8),
              MButton(
                label: 'Save note',
                kind: MButtonKind.primary,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  if (saved != true) return;
  final now = DateTime.now();
  final n = note ??
      Note(
        id: _uuid.v4(),
        title: '',
        body: '',
        courseId: courseId,
        lessonId: lessonId,
        resourceId: resourceId,
        page: page,
        timestampMs: timestampMs,
        createdAt: now,
        updatedAt: now,
      );
  await Store.i.saveNote(n.copyWith(
    title: title.text.trim().isEmpty ? 'Untitled note' : title.text.trim(),
    body: body.text,
    updatedAt: now,
  ));
  AppState.i.bump();
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.lines = 1,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: MType.label.copyWith(color: c.inkFaint, fontSize: 10)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            minLines: lines,
            maxLines: lines,
            style: MType.body.copyWith(color: c.ink),
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
  }
}