package com.droner.sms_money_tracker

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

class SmsDbHelper(context: Context) : SQLiteOpenHelper(context, "sms_money.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE transactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sms_id TEXT UNIQUE NOT NULL,
                sender TEXT,
                body TEXT,
                amount REAL NOT NULL,
                currency TEXT,
                type TEXT NOT NULL,
                counterparty TEXT,
                ts INTEGER NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX idx_ts ON transactions(ts)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}
}

object SmsDb {
    private fun db(context: Context): SQLiteDatabase =
        SmsDbHelper(context.applicationContext).writableDatabase

    fun insert(context: Context, txn: Txn): Boolean {
        val values = ContentValues().apply {
            put("sms_id", txn.smsId.toString())
            put("sender", txn.sender)
            put("body", txn.body)
            put("amount", txn.amount)
            put("currency", txn.currency)
            put("type", txn.type)
            put("counterparty", txn.counterparty)
            put("ts", txn.ts)
        }
        return db(context).insertWithOnConflict(
            "transactions", null, values, SQLiteDatabase.CONFLICT_IGNORE
        ) != -1L
    }

    fun getTransactions(context: Context, filter: String, query: String): String {
        val where = StringBuilder("1=1")
        val args = mutableListOf<String>()
        when (filter) {
            "debit" -> where.append(" AND type = 'debit'")
            "credit" -> where.append(" AND type = 'credit'")
        }
        if (query.isNotBlank()) {
            where.append(" AND (body LIKE ? OR counterparty LIKE ? OR sender LIKE ?)")
            val like = "%$query%"
            args.add(like)
            args.add(like)
            args.add(like)
        }
        val c = db(context).query(
            "transactions",
            null,
            where.toString(),
            args.toTypedArray(),
            null,
            null,
            "ts DESC",
            "500"
        )
        val arr = JSONArray()
        c.use {
            while (c.moveToNext()) {
                arr.put(
                    JSONObject().apply {
                        put("id", c.getLong(c.getColumnIndexOrThrow("id")))
                        put("sender", c.getString(c.getColumnIndexOrThrow("sender")) ?: "")
                        put("body", c.getString(c.getColumnIndexOrThrow("body")) ?: "")
                        put("amount", c.getDouble(c.getColumnIndexOrThrow("amount")))
                        put("currency", c.getString(c.getColumnIndexOrThrow("currency")) ?: "")
                        put("type", c.getString(c.getColumnIndexOrThrow("type")))
                        put("counterparty", c.getString(c.getColumnIndexOrThrow("counterparty")) ?: "")
                        put("ts", c.getLong(c.getColumnIndexOrThrow("ts")))
                    }
                )
            }
        }
        return arr.toString()
    }

    fun getSummary(context: Context): String {
        val monthStart = startOfMonth(System.currentTimeMillis())
        return JSONObject().apply {
            put("spentThisMonth", sumBy(context, "debit", monthStart))
            put("receivedThisMonth", sumBy(context, "credit", monthStart))
            put("spentTotal", sumBy(context, "debit", 0L))
            put("receivedTotal", sumBy(context, "credit", 0L))
        }.toString()
    }

    fun getMonthlyTotals(context: Context, months: Int): String {
        val arr = JSONArray()
        val cal = Calendar.getInstance()
        for (i in months - 1 downTo 0) {
            val start = startOfMonth(cal.timeInMillis)
            val end = start + 32L * 24 * 3600 * 1000
            val monthKey = "%04d-%02d".format(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1)
            arr.put(
                JSONObject().apply {
                    put("month", monthKey)
                    put("spent", sumBetween(context, "debit", start, end))
                    put("received", sumBetween(context, "credit", start, end))
                }
            )
            cal.add(Calendar.MONTH, -1)
        }
        return arr.toString()
    }

    private fun startOfMonth(time: Long): Long {
        val cal = Calendar.getInstance().apply { timeInMillis = time }
        cal.set(Calendar.DAY_OF_MONTH, 1)
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    private fun sumBy(context: Context, type: String, since: Long): Double {
        val where = if (since > 0) "type = ? AND ts >= ?" else "type = ?"
        val args = if (since > 0) arrayOf(type, since.toString()) else arrayOf(type)
        val c = db(context).rawQuery(
            "SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE $where", args
        )
        c.use { it.moveToFirst(); return it.getDouble(0) }
    }

    private fun sumBetween(context: Context, type: String, start: Long, end: Long): Double {
        val c = db(context).rawQuery(
            "SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE type = ? AND ts >= ? AND ts < ?",
            arrayOf(type, start.toString(), end.toString())
        )
        c.use { it.moveToFirst(); return it.getDouble(0) }
    }
}
