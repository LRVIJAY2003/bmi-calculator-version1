import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(

        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  var wtController = TextEditingController();
  var cmController = TextEditingController();
  var result="";


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(

        title: Text('BMI CALCULATOR'),
      ),
      body: Center(
        child: Container(
          width: 350,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('BMI', style: TextStyle(
                fontSize: 36, fontWeight: FontWeight.bold
              ),),
              SizedBox(height: 35,),
              TextField(
                controller: wtController,
                decoration: InputDecoration(
                  label: Text('ENTER YOUR WEIGHT(IN KGS)'),
                  prefixIcon: Icon(Icons.monitor_weight)
                ),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 20,),
              TextField(
                controller: cmController,
                decoration: InputDecoration(
                  label: Text('ENTER YOUR HEIGHT(IN CMS)'),
                  prefixIcon: Icon(Icons.height)
              ),
              keyboardType: TextInputType.number,
              ),
              SizedBox(height: 20,),
              ElevatedButton(onPressed: (){
                var wt= wtController.text.toString();
                var ht= cmController.text.toString();
                if(wt!="" && ht!=""){
                  var iwt=int.parse(wt);
                  var iht=int.parse(ht);
                  var tm= iht/100;
                  var bmi= iwt/(tm*tm);
                  setState(() {
                    result = " YOUR BMI IS : ${bmi.toStringAsFixed(2)}";
                  });

                }else {
                  setState(() {
                    result="YOU ARE REQUIRED TO FILL ALL THE DETAILS!!";
                  });
                }
              }, child: Text('CALCULATE')),
              SizedBox(height: 20,),
              Text(result, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold , ),)

            ],
          ),
        ),
      )
    );
  }
}
