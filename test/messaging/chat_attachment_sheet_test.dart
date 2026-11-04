import 'dart:async';
import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/features/media/presentation/controllers/chat_media_controller.dart';
import 'package:instant_messenger/features/media/presentation/controllers/gallery_picker_notifier.dart';
import 'package:instant_messenger/features/media/presentation/widgets/attachment_sheet.dart';
import 'package:instant_messenger/features/messaging/presentation/providers/messaging_providers.dart';

class MockChatSendNotifier extends ChatSendNotifier {
  final List<List<XFile>> sentImageBatches = [];
  final List<String> sentCaptions = [];
  final List<XFile> sentAudioFiles = [];
  final List<XFile> sentDocFiles = [];

  MockChatSendNotifier(super.arg);

  @override
  Future<void> sendImages(
    List<XFile> files,
    String caption, {
    required String otherName,
    String? otherAvatar,
  }) async {
    sentImageBatches.add(files);
    sentCaptions.add(caption);
  }

  @override
  Future<void> sendAudio(
    XFile file, {
    required String otherName,
    String? otherAvatar,
  }) async {
    sentAudioFiles.add(file);
  }

  @override
  Future<void> sendDocument(
    XFile file, {
    required String otherName,
    String? otherAvatar,
  }) async {
    sentDocFiles.add(file);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testArgs = ChatControllerArgs(
    chatId: 'chat_123',
    currentUserId: 'user_me',
    otherUserId: 'user_them',
  );

  group('ChatMediaController Unit Tests', () {
    test('pickFromGallery delegates to custom handler and returns files', () async {
      final fakeFiles = [XFile('/tmp/photo1.jpg'), XFile('/tmp/photo2.png')];
      final controller = ChatMediaController(
        galleryPicker: () async => fakeFiles,
      );

      final result = await controller.pickFromGallery();
      expect(result, fakeFiles);
      expect(result.length, 2);
    });

    test('pickFromGallery returns empty list when user cancels', () async {
      final controller = ChatMediaController(
        galleryPicker: () async => [],
      );

      final result = await controller.pickFromGallery();
      expect(result, isEmpty);
    });

    test('pickDocument delegates to custom handler', () async {
      final fakeDoc = XFile('/tmp/report.pdf', name: 'report.pdf');
      final controller = ChatMediaController(
        documentPicker: () async => fakeDoc,
      );

      final result = await controller.pickDocument();
      expect(result?.path, '/tmp/report.pdf');
      expect(result?.name, 'report.pdf');
    });

    test('pickAudio delegates to custom handler', () async {
      final fakeAudio = XFile('/tmp/voice.m4a');
      final controller = ChatMediaController(
        audioPicker: () async => fakeAudio,
      );

      final result = await controller.pickAudio();
      expect(result?.path, '/tmp/voice.m4a');
    });

    test('pickFromCamera delegates to custom handler', () async {
      final fakeFile = File('/tmp/camera_capture.jpg');
      final controller = ChatMediaController(
        cameraPicker: () async => fakeFile,
      );

      final result = await controller.pickFromCamera();
      expect(result?.path, '/tmp/camera_capture.jpg');
    });
  });

  group('AttachmentSheet Navigation and Dispatch Tests', () {
    testWidgets('Renders all four media options correctly', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AttachmentSheet(
                args: testArgs,
                otherName: 'Alice',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('Document'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
      expect(find.byIcon(Icons.photo), findsOneWidget);
      expect(find.byIcon(Icons.audiotrack), findsOneWidget);
      expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
    });

    testWidgets(
      'Tapping Gallery dismisses sheet once, keeps host screen mounted, and sends selected images',
      (tester) async {
        final mockSendNotifier = MockChatSendNotifier(testArgs);
        final selectedFiles = [
          XFile('/tmp/img1.jpg'),
          XFile('/tmp/img2.jpg'),
        ];

        final mockMediaPicker = ChatMediaController(
          galleryPicker: () async => selectedFiles,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatSendNotifierProvider(testArgs).overrideWith(() => mockSendNotifier),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  return Scaffold(
                    appBar: AppBar(title: const Text('Chats List Screen')),
                    body: Center(
                      child: ElevatedButton(
                        child: const Text('Open Chat'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (chatContext) => Scaffold(
                                appBar: AppBar(title: const Text('Chat with Alice')),
                                body: Center(
                                  child: ElevatedButton(
                                    key: const ValueKey('open_attachment_button'),
                                    child: const Text('Attach'),
                                    onPressed: () {
                                      showModalBottomSheet(
                                        context: chatContext,
                                        builder: (_) => AttachmentSheet(
                                          args: testArgs,
                                          otherName: 'Alice',
                                          mediaPicker: mockMediaPicker,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );

        // 1. Navigate to Chat Screen
        await tester.tap(find.text('Open Chat'));
        await tester.pumpAndSettle();
        expect(find.text('Chat with Alice'), findsOneWidget);

        // 2. Open Attachment Sheet
        await tester.tap(find.byKey(const ValueKey('open_attachment_button')));
        await tester.pumpAndSettle();
        expect(find.text('Gallery'), findsOneWidget);

        // 3. Tap Gallery
        await tester.tap(find.text('Gallery'));
        await tester.pumpAndSettle();

        // 4. Verification:
        // - AttachmentSheet is dismissed (no longer found)
        expect(find.text('Gallery'), findsNothing);
        // - Chat screen MUST still be visible (NOT popped back to Chats List Screen)
        expect(find.text('Chatwith Alice', skipOffstage: false), findsNothing);
        expect(find.text('Chat with Alice'), findsOneWidget);
        // - Images sent to notifier
        expect(mockSendNotifier.sentImageBatches.length, 1);
        expect(mockSendNotifier.sentImageBatches.first, selectedFiles);

        // 5. Reopening attachment sheet works cleanly
        await tester.tap(find.byKey(const ValueKey('open_attachment_button')));
        await tester.pumpAndSettle();
        expect(find.text('Gallery'), findsOneWidget);
        expect(find.text('Chat with Alice'), findsOneWidget);
      },
    );

    testWidgets(
      'Cancelling Gallery selection dismisses sheet without popping chat screen or sending',
      (tester) async {
        final mockSendNotifier = MockChatSendNotifier(testArgs);
        final mockMediaPicker = ChatMediaController(
          galleryPicker: () async => [], // User cancelled
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatSendNotifierProvider(testArgs).overrideWith(() => mockSendNotifier),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  return Scaffold(
                    appBar: AppBar(title: const Text('Chats List Screen')),
                    body: Center(
                      child: ElevatedButton(
                        child: const Text('Open Chat'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (chatContext) => Scaffold(
                                appBar: AppBar(title: const Text('Chat with Alice')),
                                body: Center(
                                  child: ElevatedButton(
                                    key: const ValueKey('open_attachment_button'),
                                    child: const Text('Attach'),
                                    onPressed: () {
                                      showModalBottomSheet(
                                        context: chatContext,
                                        builder: (_) => AttachmentSheet(
                                          args: testArgs,
                                          otherName: 'Alice',
                                          mediaPicker: mockMediaPicker,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Chat'));
        await tester.pumpAndSettle();
        expect(find.text('Chat with Alice'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('open_attachment_button')));
        await tester.pumpAndSettle();
        expect(find.text('Gallery'), findsOneWidget);

        await tester.tap(find.text('Gallery'));
        await tester.pumpAndSettle();

        // Sheet closed
        expect(find.text('Gallery'), findsNothing);
        // Still on chat screen
        expect(find.text('Chat with Alice'), findsOneWidget);
        // Nothing sent
        expect(mockSendNotifier.sentImageBatches, isEmpty);
      },
    );

    testWidgets('Tapping Audio dismisses sheet and dispatches audio message', (tester) async {
      final mockSendNotifier = MockChatSendNotifier(testArgs);
      final audioFile = XFile('/tmp/audio.mp3');
      final mockMediaPicker = ChatMediaController(
        audioPicker: () async => audioFile,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatSendNotifierProvider(testArgs).overrideWith(() => mockSendNotifier),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (ctx) => ElevatedButton(
                    child: const Text('Open Sheet'),
                    onPressed: () {
                      showModalBottomSheet(
                        context: ctx,
                        builder: (_) => AttachmentSheet(
                          args: testArgs,
                          otherName: 'Bob',
                          mediaPicker: mockMediaPicker,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();
      expect(find.text('Audio'), findsOneWidget);

      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();

      expect(find.text('Audio'), findsNothing);
      expect(mockSendNotifier.sentAudioFiles.length, 1);
      expect(mockSendNotifier.sentAudioFiles.first.path, '/tmp/audio.mp3');
    });

    testWidgets('Tapping Document dismisses sheet and dispatches document message', (tester) async {
      final mockSendNotifier = MockChatSendNotifier(testArgs);
      final docFile = XFile('/tmp/document.pdf', name: 'document.pdf');
      final mockMediaPicker = ChatMediaController(
        documentPicker: () async => docFile,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatSendNotifierProvider(testArgs).overrideWith(() => mockSendNotifier),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (ctx) => ElevatedButton(
                    child: const Text('Open Sheet'),
                    onPressed: () {
                      showModalBottomSheet(
                        context: ctx,
                        builder: (_) => AttachmentSheet(
                          args: testArgs,
                          otherName: 'Bob',
                          mediaPicker: mockMediaPicker,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();
      expect(find.text('Document'), findsOneWidget);

      await tester.tap(find.text('Document'));
      await tester.pumpAndSettle();

      expect(find.text('Document'), findsNothing);
      expect(mockSendNotifier.sentDocFiles.length, 1);
      expect(mockSendNotifier.sentDocFiles.first.name, 'document.pdf');
    });
  });

  group('AttachmentSheet Riverpod Disposal Lifecycle Regression Tests', () {
    testWidgets(
      'Gallery selection completing after sheet dismissal sends image without disposed-ref error',
      (tester) async {
        final mockSendNotifier = MockChatSendNotifier(testArgs);
        final selectedFiles = [XFile('/tmp/photo1.jpg')];
        final pickerCompleter = Completer<List<XFile>>();

        final mockMediaPicker = ChatMediaController(
          galleryPicker: () => pickerCompleter.future,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatSendNotifierProvider(testArgs).overrideWith(() => mockSendNotifier),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  return Scaffold(
                    appBar: AppBar(title: const Text('Chats List Screen')),
                    body: Center(
                      child: ElevatedButton(
                        child: const Text('Open Chat'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (chatContext) => Scaffold(
                                appBar: AppBar(title: const Text('Chat with Alice')),
                                body: Center(
                                  child: ElevatedButton(
                                    key: const ValueKey('open_attachment_button'),
                                    child: const Text('Attach'),
                                    onPressed: () {
                                      showModalBottomSheet(
                                        context: chatContext,
                                        builder: (_) => AttachmentSheet(
                                          args: testArgs,
                                          otherName: 'Alice',
                                          mediaPicker: mockMediaPicker,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );

        // 1. Open chat and open attachment sheet
        await tester.tap(find.text('Open Chat'));
        await tester.pumpAndSettle();
        expect(find.text('Chat with Alice'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('open_attachment_button')));
        await tester.pumpAndSettle();
        expect(find.text('Gallery'), findsOneWidget);

        // 2. Select Gallery: sheet begins dismissal while picker future is pending
        await tester.tap(find.text('Gallery'));
        // 3. Sheet dismisses and unmounts completely
        await tester.pumpAndSettle();
        expect(find.text('Gallery'), findsNothing);
        expect(find.byType(AttachmentSheet), findsNothing);

        // 4. Gallery picker returns selected image after sheet is unmounted
        pickerCompleter.complete(selectedFiles);
        await tester.pump();

        // 5. Verify no disposed-ref error occurred and images dispatched
        expect(mockSendNotifier.sentImageBatches.length, 1);
        expect(mockSendNotifier.sentImageBatches.first, selectedFiles);

        // 6. Return to chat composer and verify attachment sheet can be reopened
        expect(find.text('Chat with Alice'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('open_attachment_button')));
        await tester.pumpAndSettle();
        expect(find.text('Gallery'), findsOneWidget);
      },
    );

    testWidgets(
      'Cancelling Gallery selection after sheet dismissal completes cleanly without error',
      (tester) async {
        final mockSendNotifier = MockChatSendNotifier(testArgs);
        final pickerCompleter = Completer<List<XFile>>();

        final mockMediaPicker = ChatMediaController(
          galleryPicker: () => pickerCompleter.future,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatSendNotifierProvider(testArgs).overrideWith(() => mockSendNotifier),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  return Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        key: const ValueKey('open_attachment_button'),
                        child: const Text('Attach'),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (_) => AttachmentSheet(
                              args: testArgs,
                              otherName: 'Alice',
                              mediaPicker: mockMediaPicker,
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );

        // 1. Open attachment sheet
        await tester.tap(find.byKey(const ValueKey('open_attachment_button')));
        await tester.pumpAndSettle();
        expect(find.text('Gallery'), findsOneWidget);

        // 2. Select Gallery: sheet dismisses while picker is pending
        await tester.tap(find.text('Gallery'));
        await tester.pumpAndSettle();
        expect(find.byType(AttachmentSheet), findsNothing);

        // 3. User cancels gallery selection (returns empty list)
        pickerCompleter.complete([]);
        await tester.pump();

        // 4. Verify no error, nothing sent, sheet can be opened again
        expect(mockSendNotifier.sentImageBatches, isEmpty);
        await tester.tap(find.byKey(const ValueKey('open_attachment_button')));
        await tester.pumpAndSettle();
        expect(find.text('Gallery'), findsOneWidget);
      },
    );

    testWidgets(
      'Audio selection completing after sheet dismissal sends audio without disposed-ref error',
      (tester) async {
        final mockSendNotifier = MockChatSendNotifier(testArgs);
        final audioCompleter = Completer<XFile?>();
        final mockMediaPicker = ChatMediaController(
          audioPicker: () => audioCompleter.future,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatSendNotifierProvider(testArgs).overrideWith(() => mockSendNotifier),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  return Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        child: const Text('Attach'),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (_) => AttachmentSheet(
                              args: testArgs,
                              otherName: 'Alice',
                              mediaPicker: mockMediaPicker,
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Attach'));
        await tester.pumpAndSettle();
        expect(find.text('Audio'), findsOneWidget);

        await tester.tap(find.text('Audio'));
        await tester.pumpAndSettle();
        expect(find.byType(AttachmentSheet), findsNothing);

        audioCompleter.complete(XFile('/tmp/song.mp3'));
        await tester.pump();

        expect(mockSendNotifier.sentAudioFiles.length, 1);
        expect(mockSendNotifier.sentAudioFiles.first.path, '/tmp/song.mp3');
      },
    );

    testWidgets(
      'Document selection completing after sheet dismissal sends document without disposed-ref error',
      (tester) async {
        final mockSendNotifier = MockChatSendNotifier(testArgs);
        final docCompleter = Completer<XFile?>();
        final mockMediaPicker = ChatMediaController(
          documentPicker: () => docCompleter.future,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatSendNotifierProvider(testArgs).overrideWith(() => mockSendNotifier),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  return Scaffold(
                    body: Center(
                      child: ElevatedButton(
                        child: const Text('Attach'),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (_) => AttachmentSheet(
                              args: testArgs,
                              otherName: 'Alice',
                              mediaPicker: mockMediaPicker,
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Attach'));
        await tester.pumpAndSettle();
        expect(find.text('Document'), findsOneWidget);

        await tester.tap(find.text('Document'));
        await tester.pumpAndSettle();
        expect(find.byType(AttachmentSheet), findsNothing);

        docCompleter.complete(XFile('/tmp/contract.pdf', name: 'contract.pdf'));
        await tester.pump();

        expect(mockSendNotifier.sentDocFiles.length, 1);
        expect(mockSendNotifier.sentDocFiles.first.name, 'contract.pdf');
      },
    );

    testWidgets(
      'AttachmentSheet uses explicitly injected sendNotifier without accessing ref',
      (tester) async {
        final customSendNotifier = MockChatSendNotifier(testArgs);
        final mockMediaPicker = ChatMediaController(
          galleryPicker: () async => [XFile('/tmp/injected.png')],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (ctx) => ElevatedButton(
                    child: const Text('Attach'),
                    onPressed: () {
                      showModalBottomSheet(
                        context: ctx,
                        builder: (_) => AttachmentSheet(
                          args: testArgs,
                          otherName: 'Alice',
                          mediaPicker: mockMediaPicker,
                          sendNotifier: customSendNotifier,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Attach'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Gallery'));
        await tester.pumpAndSettle();

        expect(customSendNotifier.sentImageBatches.length, 1);
        expect(customSendNotifier.sentImageBatches.first.first.path, '/tmp/injected.png');
      },
    );
  });

  group('GalleryPickerState Unit Tests', () {
    test('Initial GalleryPickerState default values', () {
      const state = GalleryPickerState();
      expect(state.loading, isTrue);
      expect(state.entities, isEmpty);
      expect(state.items, isEmpty);
      expect(state.selectedIndexes, isEmpty);
      expect(state.selectedFiles, isEmpty);
    });

    test('copyWith updates state properties correctly', () {
      const state = GalleryPickerState();
      final updated = state.copyWith(
        loading: false,
        items: [XFile('/tmp/1.jpg')],
        selectedIndexes: {0},
      );
      expect(updated.loading, isFalse);
      expect(updated.items.length, 1);
      expect(updated.selectedIndexes, {0});
      expect(updated.selectedFiles.length, 1);
      expect(updated.isSelected(0), isTrue);
      expect(updated.isSelected(1), isFalse);
    });
  });
}
