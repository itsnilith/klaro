import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/state.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import 'module_content_dialogs.dart';

const _uuid = Uuid();

/// An interactive self-check backed by the same local cards used by Review.
/// It deliberately has no media player or remote provider dependency.
class QuizView extends StatefulWidget {
  const QuizView({super.key, required this.lesson});

  final Lesson lesson;

  @override
  State<QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<QuizView> {
  List<Flashcard> _questions = const [];
  var _index = 0;
  var _showAnswer = false;
  var _finished = false;
  var _loading = true;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant QuizView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lesson.id != widget.lesson.id) {
      _index = 0;
      _showAnswer = false;
      _finished = false;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final questions = await Store.i.cardsForLesson(widget.lesson.id);
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _index = _index.clamp(
          0,
          (questions.length - 1).clamp(0, questions.length),
        );
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'The quiz questions could not be loaded.';
      });
    }
  }

  Future<void> _addQuestion() async {
    final draft = await showQuizQuestionEditor(context);
    if (draft == null || !mounted) return;
    final now = DateTime.now();
    try {
      await Store.i.saveCard(
        Flashcard(
          id: _uuid.v4(),
          deck: 'Quiz: ${widget.lesson.title}',
          front: draft.question,
          back: draft.answer,
          courseId: widget.lesson.courseId,
          lessonId: widget.lesson.id,
          dueAt: now,
          createdAt: now,
        ),
      );
      AppState.i.bump();
      if (mounted) setState(() => _finished = false);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The question could not be saved. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _grade(int rating) async {
    if (_busy || _index >= _questions.length) return;
    setState(() => _busy = true);
    try {
      await Store.i.reviewCard(_questions[_index], rating);
      final last = _index == _questions.length - 1;
      if (last) {
        await Store.i.toggleLessonCompleted(widget.lesson.id, true);
        AppState.i.bump();
      }
      if (!mounted) return;
      setState(() {
        if (last) {
          _finished = true;
        } else {
          _index += 1;
        }
        _showAnswer = false;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your answer could not be saved. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _previous() {
    if (_index == 0) return;
    setState(() {
      _index -= 1;
      _showAnswer = false;
      _finished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(64),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return MEmpty(
        icon: Icons.error_outline_rounded,
        title: 'Cannot open this quiz',
        message: _error!,
        compact: true,
        action: MButton(
          label: 'Try again',
          onPressed: () {
            setState(() => _loading = true);
            _load();
          },
        ),
      );
    }

    return MCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.quiz_outlined, size: 20, color: c.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_questions.length} ${_questions.length == 1 ? 'question' : 'questions'} · Self-check',
                  style: MType.bodyStrong.copyWith(color: c.ink),
                ),
              ),
              MIconButton(
                icon: Icons.add_rounded,
                tooltip: 'Add quiz question',
                size: 30,
                onPressed: _addQuestion,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const MDivider(),
          if (_questions.isEmpty)
            MEmpty(
              icon: Icons.quiz_outlined,
              title: 'No questions yet',
              message:
                  'Add a question and its answer to start this self-check.',
              compact: true,
              action: MButton(
                label: 'Add question',
                kind: MButtonKind.primary,
                onPressed: _addQuestion,
              ),
            )
          else if (_finished)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  Icon(Icons.task_alt_rounded, size: 38, color: c.accent),
                  const SizedBox(height: 12),
                  Text('Quiz complete', style: MType.h2.copyWith(color: c.ink)),
                  const SizedBox(height: 6),
                  Text(
                    'Your answers were saved. These questions will return in Flashcards & Review.',
                    textAlign: TextAlign.center,
                    style: MType.small.copyWith(color: c.inkMuted, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  MButton(
                    label: 'Practice again',
                    icon: Icons.replay_rounded,
                    onPressed: () => setState(() {
                      _index = 0;
                      _showAnswer = false;
                      _finished = false;
                    }),
                  ),
                ],
              ),
            )
          else ...[
            const SizedBox(height: 18),
            Text(
              'Question ${_index + 1} of ${_questions.length}',
              style: MType.label.copyWith(color: c.inkFaint),
            ),
            const SizedBox(height: 8),
            MProgress(value: (_index + 1) / _questions.length, height: 4),
            const SizedBox(height: 20),
            SelectionArea(
              child: Text(
                _questions[_index].front,
                style: MType.h2.copyWith(
                  color: c.ink,
                  fontSize: 20,
                  height: 1.35,
                ),
              ),
            ),
            if (_showAnswer) ...[
              const SizedBox(height: 20),
              const MDivider(),
              const SizedBox(height: 16),
              Text('Answer', style: MType.label.copyWith(color: c.inkFaint)),
              const SizedBox(height: 6),
              SelectionArea(
                child: Text(
                  _questions[_index].back,
                  style: MType.body.copyWith(color: c.ink, height: 1.55),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (!_showAnswer)
              Row(
                children: [
                  if (_index > 0)
                    MButton(
                      label: 'Previous',
                      icon: Icons.arrow_back_rounded,
                      dense: true,
                      onPressed: _previous,
                    ),
                  const Spacer(),
                  MButton(
                    key: const Key('show-quiz-answer'),
                    label: 'Show answer',
                    kind: MButtonKind.primary,
                    onPressed: () => setState(() => _showAnswer = true),
                  ),
                ],
              )
            else
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  MButton(
                    key: const Key('quiz-review-again'),
                    label: 'Review again',
                    icon: Icons.replay_rounded,
                    onPressed: _busy ? null : () => _grade(0),
                  ),
                  MButton(
                    key: const Key('quiz-knew-answer'),
                    label: 'I knew it',
                    icon: Icons.check_rounded,
                    kind: MButtonKind.primary,
                    onPressed: _busy ? null : () => _grade(2),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
