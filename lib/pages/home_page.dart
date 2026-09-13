// ignore_for_file: close_sinks

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quill_fb2/pages/book_page.dart';
import 'package:quill_fb2/pages/settings_page.dart';
import 'package:quill_fb2/services/app.service.dart';
import 'package:quill_fb2/utils/common.dart';
import 'package:quill_fb2/utils/consts.dart';
import 'package:quill_fb2/widgets/loading.dialog.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  final AppService service;
  HomeScreen(this.service);
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool isLoading = false;
  StreamController<void>? changeController;
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    changeController!.close();
    super.dispose();
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    changeController = StreamController<void>.broadcast();
    super.initState();
    changeController!.stream.asBroadcastStream().listen((event) {
      try {
        print('HomeScreen.update history list');
      } catch (e) {
        print(e);
      }
    });
  }

  @override
  void reassemble() {
    super.reassemble();
  }

  _openProject(Map project) async {
    setState(() {
      isLoading = true;
    });
    final xmlFileInfo = await widget.service.loadBook(project);
    await Future.delayed(Duration(seconds: 1));
    try {
      final json = await widget.service.convertXmlToJson(xmlFileInfo.data);
      await Future.delayed(Duration(seconds: 1));
      final book = await widget.service.addProject(json, xmlFileInfo, project);
      if (book != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                BookPage(widget.service, book, changeController),
          ),
        ).then((value) => setState(() {}));
      }
    } catch (e) {
      print(e);
    }
    setState(() {
      isLoading = false;
    });
  }

  _loadFile() async {
    setState(() {
      isLoading = true;
    });
    final xmlFileInfo =
        await widget.service.openFile({'fb2': true, 'zip': true});
    await Future.delayed(Duration(seconds: 1));
    try {
      final json = await widget.service.convertXmlToJson(xmlFileInfo.data);
      await Future.delayed(Duration(seconds: 1));
      final book = await widget.service.addProject(json, xmlFileInfo, null);
      if (book != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                BookPage(widget.service, book, changeController),
          ),
        ).then((value) => setState(() {}));
      }
    } catch (e) {
      print(e);
    }
    setState(() {
      isLoading = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Map settings = widget.service.getSettings();
    bool autoSave = stringToBool(settings["auto-save"]) ?? false;
    print('page.state = ${state.name} - autoSave=$autoSave');
    print(autoSave);
  }

  @override
  Widget build(BuildContext context) {
    final ModalRoundedProgressBar progressBar =
        ModalRoundedProgressBar(0.95, "Loading");
    List<Widget> stackItems = [];
    final scaffold = Scaffold(
        appBar: AppBar(
          title: Text(
            widget.service.translate(LangTranslateItems.appTitle),
          ),
          centerTitle: true,
          actions: [
            Padding(
              padding: EdgeInsets.all(8.0),
              child: GestureDetector(
                  onTap: () async {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SettingsScreen(widget.service),
                      ),
                    ).then((value) => setState(() {}));
                  },
                  child: Icon(Icons.settings)),
            )
          ],
        ),
        body: Column(
          children: [
            Card(child: CurrentProject(widget.service, _loadFile)),
            ProjectHistory(widget.service, _openProject)
          ],
        ));
    stackItems.add(scaffold);
    if (isLoading) stackItems.add(progressBar);

    return Stack(
      children: stackItems,
    );
  }
}

class CurrentProject extends StatefulWidget {
  final AppService service;
  final Function loadFile;
  CurrentProject(this.service, this.loadFile);
  @override
  _CurrentProjectState createState() => _CurrentProjectState();
}

class _CurrentProjectState extends State<CurrentProject> {
  @override
  Widget build(BuildContext context) {
    Widget child;
    child = new GestureDetector(
        onTap: () async {
          await widget.loadFile();
        },
        child: Center(
            child: SizedBox.fromSize(
          size: Size(120, 100), // button width and height
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10.0),
            child: Material(
              color: Colors.lightBlue[100], // button color
              child: InkWell(
                splashColor: Colors.white, // splash color
                onTap: () async {
                  await widget.loadFile();
                }, // button pressed
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.add, color: Colors.black), // icon
                    Text(
                        widget.service
                            .translate(LangTranslateItems.buttonLoadBook),
                        style: TextStyle(color: Colors.black)), // text
                  ],
                ),
              ),
            ),
          ),
        )));
    return Container(
        height: 150,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(20.0)),
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 10.0),
            ]),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          child: child,
        ));
  }
}

class ProjectHistory extends StatefulWidget {
  final AppService service;
  final Function(Map book) openProject;
  ProjectHistory(this.service, this.openProject);
  @override
  _ProjectHistoryState createState() => _ProjectHistoryState();
}

class _ProjectHistoryState extends State<ProjectHistory> {
  ScrollController controller = ScrollController();
  List<Widget> itemsData = [];
  bool closeTopContainer = false;
  double topContainer = 0;
  void getPostsData() {
    Map workspace = widget.service.workspace;

    List history = workspace["history"];
    final reversedList = new List.from(history.reversed);
    // List<dynamic> responseList = FOOD_DATA;
    List<Widget> listItems = [];
    reversedList.forEach((post) {
      listItems.add(GestureDetector(
          onTap: () => {widget.openProject(post)},
          child: Container(
              height: 150,
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(20.0)),
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withAlpha(100), blurRadius: 10.0),
                  ]),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
                child: Stack(
                  children: [
                    BookInfo(post, widget.service),
                    // Add your existing row & it's child here,
                    Positioned(
                      child: SizedBox(
                        height: 32.0,
                        width: 32.0,
                        child: FittedBox(
                          child: FloatingActionButton(
                              heroTag: 'bookPage',
                              backgroundColor: Colors.red,
                              mini: true,
                              child: Icon(Icons.delete),
                              shape: BeveledRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                              onPressed: () async {
                                await widget.service.removeProject(post);
                                setState(() {
                                  itemsData = listItems;
                                });
                              }),
                        ),
                      ),
                      right: 0,
                      top: 0,
                    )
                  ],
                ),
              ))));
    });
    setState(() {
      itemsData = listItems;
    });
  }

  @override
  void initState() {
    super.initState();

    controller.addListener(() {
      double value = controller.offset / 119;

      setState(() {
        topContainer = value;
        closeTopContainer = controller.offset > 50;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    getPostsData();
    return Expanded(
        child: ListView.builder(
            controller: controller,
            itemCount: itemsData.length,
            physics: BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              double scale = 1.0;
              if (topContainer > 0.5) {
                scale = index + 0.5 - topContainer;
                if (scale < 0) {
                  scale = 0;
                } else if (scale > 1) {
                  scale = 1;
                }
              }
              return Opacity(
                opacity: scale,
                child: Transform(
                  transform: Matrix4.identity()..scale(scale, scale),
                  alignment: Alignment.bottomCenter,
                  child: Align(
                      heightFactor: 0.7,
                      alignment: Alignment.topCenter,
                      child: itemsData[index]),
                ),
              );
            }));
  }
}

class CircularImage extends StatelessWidget {
  final ImageProvider image;

  CircularImage(this.image);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100.0,
      height: 130.0,
      decoration: new BoxDecoration(
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.all(Radius.circular(10)),
          border: Border.all(
              color: Colors.teal, width: 2.0, style: BorderStyle.solid),
          image: new DecorationImage(fit: BoxFit.cover, image: image)),
    );
  }
}

class BookInfo extends StatelessWidget {
  final Map info;
  final AppService service;
  BookInfo(this.info, this.service);
  @override
  Widget build(BuildContext context) {
    String updated = safeGet(info, 'updated', DateTime.now().toString());
    String version = safeGet(info, 'version', "");
    String sequence = safeGet(info, 'sequence', "");
    DateTime date = DateTime.parse(updated);
    String dateStr = DateFormat("dd-MM-yyyy").format(date);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              info["author"] ?? '-',
              style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  fontWeight: FontWeight.bold),
            ),
            Text(
              "[ $dateStr ] $sequence ( $version )",
              style: const TextStyle(fontSize: 12, color: Colors.black),
            ),
            Span(
              info["title"] ?? 'Unknow',
              220.0,
              0.0,
              const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            )
          ],
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
          CircularImage(service.base64Image(safeGet(info, 'cover', ''), true))
        ])
      ],
    );
  }
}

class Span extends StatelessWidget {
  final String text;
  final double width;
  final double padding;
  final TextStyle style;
  Span(this.text, this.width, this.padding, this.style);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      width: width,
      child: new Column(
        children: <Widget>[
          new Text(text, style: style, textAlign: TextAlign.left),
        ],
      ),
    );
  }
}
